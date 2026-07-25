//! Single DINOv2 encoder block (RF-DETR variant).
//!
//! Shape: pre-norm transformer block with LayerScale on each sub-path:
//!
//! ```text
//! x  ──┬──  norm1 ── attn ── ls1 ──┐    ┌─ norm2 ── mlp ── ls2 ──┐
//!      │                           +    │                        +    ──> y
//!      └──────────── residual ────┘    └──────────  residual ───┘
//! ```
//!
//! For windowed-attention layers (the default for 9 of 12 blocks),
//! the input is `(B*4, 145, 384)`. For full-attention layers (3, 6, 9),
//! the layer first reshapes to `(B, 4*145, 384)` before attention,
//! reshapes back after — see `EncoderBlock::forward(.., run_full_attention=true)`.

use mlx_rs::{fast, nn, ops, Array};

use crate::weights::Weights;
use crate::{Error, Result};

/// When true, run Q/K/V as one fused `(384, 1152)` matmul + split.
/// When false, three separate `(384, 384)` matmuls.
///
/// Counterintuitive history: with the original encoder block (per-layer
/// eval, separate LayerScale ops) fused QKV regressed ~20% on M-series
/// because MLX was already dispatching the three small same-shape
/// matmuls in parallel and fusing serialised them. After (a) tail-eval
/// of the whole 12-block stack and (b) folding LayerScale into
/// `out_proj`/`fc2`, the per-block path is short enough that GPU
/// scheduling dominates differently and fused QKV is ~3% faster (one
/// kernel dispatch instead of three; bias-add fused into addmm). Keep
/// this toggle so the regression test is one-line if MLX re-optimises.
const USE_FUSED_QKV: bool = true;

const HIDDEN_DIM: i32 = 384;
const NUM_HEADS: i32 = 6;
const HEAD_DIM: i32 = HIDDEN_DIM / NUM_HEADS; // 64
                                              // MLP expands hidden_dim by mlp_ratio=4 -> 1536. Implicit in fc1/fc2 weights.
const LAYER_NORM_EPS: f32 = 1e-6;

const NUM_WINDOWS_SQ: i32 = 4; // num_windows^2 = 2^2

/// Loaded weight tensors for one block. We hold owned [`Array`] clones
/// so each `forward` doesn't have to re-look-up by string.
struct BlockWeights {
    norm1_w: Array,
    norm1_b: Array,
    /// Stack of `q_w | k_w | v_w` along out-dim → `(384, 1152)`. Used
    /// when `USE_FUSED_QKV` is true. Three same-shape matmuls become
    /// one — measure on each MLX/hardware combo before flipping.
    qkv_w: Array,
    qkv_b: Array, // (1152,)
    q_w: Array,
    q_b: Array,
    k_w: Array,
    k_b: Array,
    v_w: Array,
    v_b: Array,
    /// `out_w * ls1` — fold LayerScale-1 into out_proj's weight. Saves a
    /// per-channel multiply per block per forward; still mathematically
    /// identical because `linear(x, w, b) * s == linear(x, w*s, b*s)`
    /// for per-output-channel `s`.
    out_w: Array, // (in=384, out=384), already scaled by ls1
    out_b: Array, // (384,), already scaled by ls1
    norm2_w: Array,
    norm2_b: Array,
    fc1_w: Array, // (in=384, out=1536) — ONNX layout
    fc1_b: Array,
    /// `fc2_w * ls2` — same fold for LayerScale-2 into fc2.
    fc2_w: Array, // (in=1536, out=384), already scaled by ls2
    fc2_b: Array, // (384,), already scaled by ls2
}

impl BlockWeights {
    fn load(w: &Weights, layer: usize) -> Result<Self> {
        let p = format!("backbone.0.encoder.encoder.encoder.layer.{layer}");
        // Fused QKV path (whether or not we end up using it at runtime):
        // stack the three (384, 384) projections + their biases.
        let q_w_raw = w.get(&format!("{p}.attention.attention.query.weight"))?;
        let k_w_raw = w.get(&format!("{p}.attention.attention.key.weight"))?;
        let v_w_raw = w.get(&format!("{p}.attention.attention.value.weight"))?;
        let q_b_raw = w.get(&format!("{p}.attention.attention.query.bias"))?;
        let k_b_raw = w.get(&format!("{p}.attention.attention.key.bias"))?;
        let v_b_raw = w.get(&format!("{p}.attention.attention.value.bias"))?;
        let qkv_w = ops::concatenate_axis(&[q_w_raw, k_w_raw, v_w_raw], 1)
            .map_err(|e| Error::Inference(format!("layer.{layer}: qkv_w cat: {e}")))?;
        let qkv_w = crate::util::contiguous(&qkv_w)?;
        let qkv_b = ops::concatenate_axis(&[q_b_raw, k_b_raw, v_b_raw], 0)
            .map_err(|e| Error::Inference(format!("layer.{layer}: qkv_b cat: {e}")))?;
        let qkv_b = crate::util::contiguous(&qkv_b)?;
        // Fold LayerScale into out_proj and fc2: pre-multiply weight +
        // bias by the (384,) gamma vector. Broadcasts along the out dim.
        let ls1 = w.get(&format!("{p}.layer_scale1.lambda1"))?;
        let ls2 = w.get(&format!("{p}.layer_scale2.lambda1"))?;
        let out_w_raw = w.get(&format!("{p}.attention.output.dense.weight"))?;
        let out_b_raw = w.get(&format!("{p}.attention.output.dense.bias"))?;
        let out_w = out_w_raw
            .multiply(ls1)
            .map_err(|e| Error::Inference(format!("layer.{layer}: out_w*ls1: {e}")))?;
        let out_w = crate::util::contiguous(&out_w)?;
        let out_b = out_b_raw
            .multiply(ls1)
            .map_err(|e| Error::Inference(format!("layer.{layer}: out_b*ls1: {e}")))?;
        let out_b = crate::util::contiguous(&out_b)?;
        let fc2_w_raw = w.get(&format!("{p}.mlp.fc2.weight"))?;
        let fc2_b_raw = w.get(&format!("{p}.mlp.fc2.bias"))?;
        let fc2_w = fc2_w_raw
            .multiply(ls2)
            .map_err(|e| Error::Inference(format!("layer.{layer}: fc2_w*ls2: {e}")))?;
        let fc2_w = crate::util::contiguous(&fc2_w)?;
        let fc2_b = fc2_b_raw
            .multiply(ls2)
            .map_err(|e| Error::Inference(format!("layer.{layer}: fc2_b*ls2: {e}")))?;
        let fc2_b = crate::util::contiguous(&fc2_b)?;
        Ok(Self {
            norm1_w: w.get(&format!("{p}.norm1.weight"))?.deep_clone(),
            norm1_b: w.get(&format!("{p}.norm1.bias"))?.deep_clone(),
            qkv_w,
            qkv_b,
            q_w: q_w_raw.deep_clone(),
            q_b: q_b_raw.deep_clone(),
            k_w: k_w_raw.deep_clone(),
            k_b: k_b_raw.deep_clone(),
            v_w: v_w_raw.deep_clone(),
            v_b: v_b_raw.deep_clone(),
            out_w,
            out_b,
            norm2_w: w.get(&format!("{p}.norm2.weight"))?.deep_clone(),
            norm2_b: w.get(&format!("{p}.norm2.bias"))?.deep_clone(),
            fc1_w: w.get(&format!("{p}.mlp.fc1.weight"))?.deep_clone(),
            fc1_b: w.get(&format!("{p}.mlp.fc1.bias"))?.deep_clone(),
            fc2_w,
            fc2_b,
        })
    }
}

pub struct EncoderBlock {
    weights: BlockWeights,
    layer_idx: usize,
}

impl EncoderBlock {
    pub fn from_weights(w: &Weights, layer: usize) -> Result<Self> {
        Ok(Self {
            weights: BlockWeights::load(w, layer)?,
            layer_idx: layer,
        })
    }

    /// Run the block.
    /// - `x`: `(B*4, 145, 384)` for a windowed layer, `(B, 4*145, 384)`
    ///   never directly — we always take the windowed shape and
    ///   internally un-window when `full_attention=true`.
    /// - `full_attention`: if `true`, this block reshapes the windowed
    ///   tokens into a single un-windowed sequence for the attention
    ///   step, then re-windows for the post-attention residual.
    pub fn forward(&self, x: &Array, full_attention: bool) -> Result<Array> {
        // `clone` is a cheap refcount bump on the lazy graph node — no data
        // copy. We only need a handle that outlives the borrow of `x`.
        let shortcut = x.clone();

        // Norm1.
        let y = fast::layer_norm(
            x,
            Some(&self.weights.norm1_w),
            Some(&self.weights.norm1_b),
            LAYER_NORM_EPS,
        )
        .map_err(|e| self.err(format!("norm1: {e}")))?;

        // For full-attention layers, undo the window split for the attn step.
        let attn_input = if full_attention {
            let s = y.shape();
            let (b_win, l, c) = (s[0], s[1], s[2]);
            assert_eq!(b_win % NUM_WINDOWS_SQ, 0);
            y.reshape(&[b_win / NUM_WINDOWS_SQ, l * NUM_WINDOWS_SQ, c])
                .map_err(|e| self.err(format!("full-attn reshape pre: {e}")))?
        } else {
            y
        };

        // Self-attention: Q/K/V projections + SDPA + output projection.
        let attn_out = self.self_attention(&attn_input)?;

        // Re-window the attn output before residual.
        let attn_windowed = if full_attention {
            let s = attn_out.shape();
            let (b, l4, c) = (s[0], s[1], s[2]);
            attn_out
                .reshape(&[b * NUM_WINDOWS_SQ, l4 / NUM_WINDOWS_SQ, c])
                .map_err(|e| self.err(format!("full-attn reshape post: {e}")))?
        } else {
            attn_out
        };

        // ls1 already folded into out_proj's weight + bias at load time.
        let after_residual_1 = attn_windowed
            .add(&shortcut)
            .map_err(|e| self.err(format!("residual1: {e}")))?;

        // Norm2 + MLP + residual #2 (ls2 folded into fc2 at load).
        let y2 = fast::layer_norm(
            &after_residual_1,
            Some(&self.weights.norm2_w),
            Some(&self.weights.norm2_b),
            LAYER_NORM_EPS,
        )
        .map_err(|e| self.err(format!("norm2: {e}")))?;
        let mlp_out = self.mlp_forward(&y2)?;
        let out = mlp_out
            .add(&after_residual_1)
            .map_err(|e| self.err(format!("residual2: {e}")))?;
        Ok(out)
    }

    /// Self-attention (multi-head, scaled-dot-product). Input + output
    /// shape: `(B, L, C)`.
    fn self_attention(&self, x: &Array) -> Result<Array> {
        let s = x.shape();
        let (b, l, c) = (s[0], s[1], s[2]);
        debug_assert_eq!(c, HIDDEN_DIM);

        // See `USE_FUSED_QKV` for why three matmuls is faster on M-series.
        let (q, k, v) = if USE_FUSED_QKV {
            let qkv = linear(x, &self.weights.qkv_w, &self.weights.qkv_b)?;
            let parts = ops::split_sections(&qkv, &[HIDDEN_DIM, 2 * HIDDEN_DIM], -1)
                .map_err(|e| self.err(format!("qkv split: {e}")))?;
            (parts[0].clone(), parts[1].clone(), parts[2].clone())
        } else {
            let q = linear(x, &self.weights.q_w, &self.weights.q_b)?;
            let k = linear(x, &self.weights.k_w, &self.weights.k_b)?;
            let v = linear(x, &self.weights.v_w, &self.weights.v_b)?;
            (q, k, v)
        };

        // (B, L, H*Dh) -> (B, H, L, Dh)
        let q4 = head_split(&q, b, l)?;
        let k4 = head_split(&k, b, l)?;
        let v4 = head_split(&v, b, l)?;

        let scale = 1.0 / (HEAD_DIM as f32).sqrt();
        let ctx = fast::scaled_dot_product_attention(&q4, &k4, &v4, scale, None)
            .map_err(|e| self.err(format!("sdpa: {e}")))?;

        // (B, H, L, Dh) -> (B, L, H, Dh) -> (B, L, H*Dh)
        let ctx_t = ctx
            .transpose_axes(&[0, 2, 1, 3])
            .map_err(|e| self.err(format!("ctx transpose: {e}")))?;
        let ctx_flat = ctx_t
            .reshape(&[b, l, HIDDEN_DIM])
            .map_err(|e| self.err(format!("ctx flatten: {e}")))?;

        // Output projection.
        linear(&ctx_flat, &self.weights.out_w, &self.weights.out_b)
    }

    fn mlp_forward(&self, x: &Array) -> Result<Array> {
        let h = linear(x, &self.weights.fc1_w, &self.weights.fc1_b)?;
        // DINOv2 uses standard GELU (the "gelu" string, not gelu_new).
        let h_act = nn::gelu(&h).map_err(|e| self.err(format!("gelu: {e}")))?;
        linear(&h_act, &self.weights.fc2_w, &self.weights.fc2_b)
    }

    fn err(&self, msg: impl Into<String>) -> Error {
        Error::Inference(format!("layer.{}: {}", self.layer_idx, msg.into()))
    }
}

/// `x @ w + b`.
///
/// Important: ONNX-exported Linear weights ship as `(in_features,
/// out_features)`, *not* PyTorch's `(out, in)` state-dict layout —
/// the exporter inverts so the graph's MatMul takes them directly.
/// So no `.t()` here.
fn linear(x: &Array, w_in_out: &Array, b: &Array) -> Result<Array> {
    ops::addmm(b, x, w_in_out, None, None)
        .map_err(|e| Error::Inference(format!("linear addmm: {e}")))
}

/// `(B, L, H*Dh) -> (B, H, L, Dh)` — split heads + permute so the last
/// two axes match SDPA's expectation. Returns a strided view; tried
/// adding `mlx_contiguous` here but SDPA's internal copy is cheaper
/// than an extra materialize.
fn head_split(x: &Array, b: i32, l: i32) -> Result<Array> {
    let split = x
        .reshape(&[b, l, NUM_HEADS, HEAD_DIM])
        .map_err(|e| Error::Inference(format!("head split reshape: {e}")))?;
    split
        .transpose_axes(&[0, 2, 1, 3])
        .map_err(|e| Error::Inference(format!("head split permute: {e}")))
}
