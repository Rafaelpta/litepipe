//! Backbone projector — un-windows the 4 multi-scale features, merges
//! them along channels, runs a YOLO-style C2f block to produce the
//! single 256-channel feature map consumed by the LWDETR decoder.
//!
//! Param-name layout in the safetensors (post-rename):
//! ```text
//! backbone.0.projector.stages.0.0.cv1.conv.weight        (256, 1536, 1, 1)
//! backbone.0.projector.stages.0.0.cv1.bn.{weight,bias}   (256,)         LayerNorm2d
//! backbone.0.projector.stages.0.0.m.{0,1,2}.cv{1,2}.{conv,bn}.*  Bottleneck blocks
//! backbone.0.projector.stages.0.0.cv2.conv.weight        (256, 640, 1, 1)
//! backbone.0.projector.stages.0.0.cv2.bn.{weight,bias}   (256,)
//! backbone.0.projector.stages.0.1.{weight,bias}          (256,)         final LN
//! ```
//!
//! Note: the "bn" naming is legacy from BatchNorm. RF-DETR-Nano uses
//! `LayerNorm2d` (LN over the channel dim of an NCHW tensor) when
//! `layer_norm=True`. With MLX's natively-NHWC tensors, LN over the
//! last dim *is* the LayerNorm2d behavior — so we use `fast::layer_norm`
//! directly with no permute.

use mlx_rs::{fast, ops, Array};

use crate::weights::Weights;
use crate::{Error, Result};

const HIDDEN_PROJ: i32 = 256;
const C2F_HIDDEN: i32 = 128; // 256 / 2
const NUM_BOTTLENECKS: usize = 3;
const LN_EPS: f32 = 1e-6;

/// Pre-transposed conv weight: ONNX (out, in, kH, kW) → MLX (out, kH, kW, in).
fn conv_w(w: &Weights, name: &str) -> Result<Array> {
    let raw = w.get(name)?;
    let t = raw
        .transpose_axes(&[0, 2, 3, 1])
        .map_err(|e| Error::Inference(format!("conv_w {name}: {e}")))?;
    crate::util::contiguous(&t)
}

/// `Conv2d (no bias) → LN over channel-dim → SiLU`.
struct ConvLnSilu {
    weight: Array, // NHWC
    ln_w: Array,
    ln_b: Array,
    stride: (i32, i32),
    padding: (i32, i32),
}

impl ConvLnSilu {
    fn load(w: &Weights, prefix: &str, stride: (i32, i32), padding: (i32, i32)) -> Result<Self> {
        Ok(Self {
            weight: conv_w(w, &format!("{prefix}.conv.weight"))?,
            ln_w: w.get(&format!("{prefix}.bn.weight"))?.deep_clone(),
            ln_b: w.get(&format!("{prefix}.bn.bias"))?.deep_clone(),
            stride,
            padding,
        })
    }

    /// Input + output: NHWC.
    fn forward(&self, x: &Array) -> Result<Array> {
        let y = ops::conv2d(x, &self.weight, self.stride, self.padding, (1, 1), 1)
            .map_err(|e| Error::Inference(format!("ConvLnSilu conv2d: {e}")))?;
        let lnd = fast::layer_norm(&y, Some(&self.ln_w), Some(&self.ln_b), LN_EPS)
            .map_err(|e| Error::Inference(format!("ConvLnSilu LN: {e}")))?;
        // SiLU = x * sigmoid(x). MLX has it in nn::activation.
        mlx_rs::nn::silu(&lnd).map_err(|e| Error::Inference(format!("silu: {e}")))
    }
}

/// `Bottleneck`: `cv2(cv1(x))`. Both convs are 3×3 same-pad.
///
/// MultiScaleProjector passes `shortcut=False` (default in C2f) when
/// instantiating the bottleneck stack, so there is no residual add —
/// confirmed against the ONNX dump (no `Add` ops inside `m.{0..2}`).
struct Bottleneck {
    cv1: ConvLnSilu,
    cv2: ConvLnSilu,
}

impl Bottleneck {
    fn load(w: &Weights, prefix: &str) -> Result<Self> {
        Ok(Self {
            cv1: ConvLnSilu::load(w, &format!("{prefix}.cv1"), (1, 1), (1, 1))?,
            cv2: ConvLnSilu::load(w, &format!("{prefix}.cv2"), (1, 1), (1, 1))?,
        })
    }

    fn forward(&self, x: &Array) -> Result<Array> {
        let h1 = self.cv1.forward(x)?;
        self.cv2.forward(&h1)
    }
}

/// `C2f` (YOLO-style): split → bottleneck stack → concat → reduce.
///
/// Input/output are NHWC tensors of shape `(B, H, W, C_in/out)`.
struct C2fBlock {
    cv1: ConvLnSilu,              // c_in → 2*hidden, 1×1
    bottlenecks: Vec<Bottleneck>, // n×Bottleneck(hidden, hidden)
    cv2: ConvLnSilu,              // (2 + n)*hidden → c_out, 1×1
}

impl C2fBlock {
    fn load(w: &Weights, prefix: &str) -> Result<Self> {
        let cv1 = ConvLnSilu::load(w, &format!("{prefix}.cv1"), (1, 1), (0, 0))?;
        let bottlenecks = (0..NUM_BOTTLENECKS)
            .map(|i| Bottleneck::load(w, &format!("{prefix}.m.{i}")))
            .collect::<Result<Vec<_>>>()?;
        let cv2 = ConvLnSilu::load(w, &format!("{prefix}.cv2"), (1, 1), (0, 0))?;
        Ok(Self {
            cv1,
            bottlenecks,
            cv2,
        })
    }

    /// NHWC in → NHWC out.
    fn forward(&self, x: &Array) -> Result<Array> {
        // cv1 maps c_in → 2*hidden, then split along channel dim.
        let y0 = self.cv1.forward(x)?;
        let parts =
            ops::split(&y0, 2, 3).map_err(|e| Error::Inference(format!("C2f cv1 split: {e}")))?;
        // y[-1] is fed forward; we collect all parts for the final concat.
        let mut chunks: Vec<Array> = parts;
        for b in &self.bottlenecks {
            let nxt = b.forward(chunks.last().expect("at least 2 chunks"))?;
            chunks.push(nxt);
        }
        let refs: Vec<&Array> = chunks.iter().collect();
        let merged = ops::concatenate_axis(&refs, 3)
            .map_err(|e| Error::Inference(format!("C2f concat: {e}")))?;
        self.cv2.forward(&merged)
    }
}

/// Final LayerNorm applied to the C2f output.
///
/// Layout: NHWC, normalize over the last (C) axis — equivalent to upstream's
/// `LayerNorm2d` over NCHW's channel dim.
struct FinalLn {
    w: Array,
    b: Array,
}

impl FinalLn {
    fn load(w: &Weights, prefix: &str) -> Result<Self> {
        Ok(Self {
            w: w.get(&format!("{prefix}.weight"))?.deep_clone(),
            b: w.get(&format!("{prefix}.bias"))?.deep_clone(),
        })
    }

    fn forward(&self, x: &Array) -> Result<Array> {
        fast::layer_norm(x, Some(&self.w), Some(&self.b), LN_EPS)
            .map_err(|e| Error::Inference(format!("Projector final LN: {e}")))
    }
}

/// Backbone projector: 4 multi-scale features → 1 single-scale 256-d feature.
pub struct Projector {
    c2f: C2fBlock,
    final_ln: FinalLn,
}

impl Projector {
    pub fn from_weights(w: &Weights) -> Result<Self> {
        Ok(Self {
            c2f: C2fBlock::load(w, "backbone.0.projector.stages.0.0")?,
            final_ln: FinalLn::load(w, "backbone.0.projector.stages.0.1")?,
        })
    }

    /// Inputs: 4 windowed feature tensors, each `(B*4, 145, 384)` from
    /// the encoder's `forward`. We:
    ///   1. Strip the cls token to get `(B*4, 144, 384)`
    ///   2. Un-window each scale to `(B, 24, 24, 384)` NHWC
    ///   3. Concatenate along channels to `(B, 24, 24, 1536)`
    ///   4. C2f → `(B, 24, 24, 256)`
    ///   5. Final LN → `(B, 24, 24, 256)` (still NHWC)
    pub fn forward(&self, encoder_outs: &[Array; 4]) -> Result<Array> {
        let unwindowed: Vec<Array> = encoder_outs
            .iter()
            .map(|e| unwindow_to_nhwc(e))
            .collect::<Result<Vec<_>>>()?;
        let refs: Vec<&Array> = unwindowed.iter().collect();
        let concat = ops::concatenate_axis(&refs, 3)
            .map_err(|e| Error::Inference(format!("Projector concat: {e}")))?;
        let c2f_out = self.c2f.forward(&concat)?;
        self.final_ln.forward(&c2f_out)
    }

    /// Convenience: run the projector and immediately produce the
    /// `(B, 576, 256)` flattened-token tensor that the encoder output
    /// projection consumes.
    pub fn forward_flat(&self, encoder_outs: &[Array; 4]) -> Result<Array> {
        let nhwc = self.forward(encoder_outs)?;
        let s = nhwc.shape();
        nhwc.reshape(&[s[0], s[1] * s[2], s[3]])
            .map_err(|e| Error::Inference(format!("Projector flatten: {e}")))
    }
}

/// Test-only: run the projector but stop after cv1's conv (no LN/SiLU).
/// Used to localize regressions inside C2f.
pub fn test_after_cv1_conv(encoder_outs: &[Array; 4], w: &Weights) -> Result<Array> {
    let unwindowed: Vec<Array> = encoder_outs
        .iter()
        .map(unwindow_to_nhwc)
        .collect::<Result<Vec<_>>>()?;
    let refs: Vec<&Array> = unwindowed.iter().collect();
    let concat = ops::concatenate_axis(&refs, 3)
        .map_err(|e| Error::Inference(format!("test cv1 concat: {e}")))?;
    let cv1_w = conv_w(w, "backbone.0.projector.stages.0.0.cv1.conv.weight")?;
    ops::conv2d(&concat, &cv1_w, (1, 1), (0, 0), (1, 1), 1)
        .map_err(|e| Error::Inference(format!("test cv1 conv2d: {e}")))
}

/// Test-only: full cv1 (conv + LN + SiLU) on un-windowed concat.
pub fn test_cv1_full(encoder_outs: &[Array; 4], w: &Weights) -> Result<Array> {
    let unwindowed: Vec<Array> = encoder_outs
        .iter()
        .map(unwindow_to_nhwc)
        .collect::<Result<Vec<_>>>()?;
    let refs: Vec<&Array> = unwindowed.iter().collect();
    let concat = ops::concatenate_axis(&refs, 3)
        .map_err(|e| Error::Inference(format!("test_cv1_full concat: {e}")))?;
    let cv1 = ConvLnSilu::load(w, "backbone.0.projector.stages.0.0.cv1", (1, 1), (0, 0))?;
    cv1.forward(&concat)
}

/// Test-only: build the un-windowed concat directly without running C2f.
/// Returns the (B, 24, 24, 1536) tensor that is the input to `cv1.conv`.
pub fn test_concat_unwindowed(encoder_outs: &[Array; 4]) -> Result<Array> {
    let unwindowed: Vec<Array> = encoder_outs
        .iter()
        .map(unwindow_to_nhwc)
        .collect::<Result<Vec<_>>>()?;
    let refs: Vec<&Array> = unwindowed.iter().collect();
    ops::concatenate_axis(&refs, 3).map_err(|e| Error::Inference(format!("test concat: {e}")))
}

/// Reverses the encoder's window partition to recover an `(B, 24, 24, 384)`
/// NHWC feature map. Strips the cls token first.
///
/// Forward windowing was:
///   `(B, 24, 24, C)` → reshape `(B*W, 12, W, 12, C)` → permute `(0,2,1,3,4)`
///   → reshape `(B*W*W, 144, C)`, then prepend cls.
///
/// So undo: drop cls → `(B*4, 144, C)` → reshape `(B*W, W, 12, 12, C)`
///         → permute `(0,2,1,3,4)` → reshape `(B, 24, 24, C)`.
fn unwindow_to_nhwc(scale: &Array) -> Result<Array> {
    let s = scale.shape();
    let (b_win, l, c) = (s[0], s[1], s[2]);
    debug_assert_eq!(l, 145);
    // Strip cls (slice axis=1, indices [1..])
    let parts = ops::split_sections(scale, &[1], 1)
        .map_err(|e| Error::Inference(format!("unwindow split cls: {e}")))?;
    let patches = &parts[1]; // (B*4, 144, C)

    let num_win = 2; // num_windows
    let patches_per_win = 12;
    let b = b_win / (num_win * num_win);
    let r1 = patches
        .reshape(&[b * num_win, num_win, patches_per_win, patches_per_win, c])
        .map_err(|e| Error::Inference(format!("unwindow reshape #1: {e}")))?;
    let r2 = r1
        .transpose_axes(&[0, 2, 1, 3, 4])
        .map_err(|e| Error::Inference(format!("unwindow permute: {e}")))?;
    // Materialize before final reshape — the strided permute would
    // otherwise force a hidden copy inside reshape, fused with the
    // `concatenate_axis` that follows.
    let r2c = crate::util::contiguous(&r2)?;
    r2c.reshape(&[b, 24, 24, c])
        .map_err(|e| Error::Inference(format!("unwindow reshape #2: {e}")))
}

#[allow(dead_code)]
const _: i32 = HIDDEN_PROJ;
#[allow(dead_code)]
const _: i32 = C2F_HIDDEN;
