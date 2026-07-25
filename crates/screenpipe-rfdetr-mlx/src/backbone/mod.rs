//! DINOv2-small backbone (RF-DETR variant).
//!
//! 12-block ViT, dim=384, heads=6, patch=16, input=384×384. Differs from
//! upstream DINOv2 in two ways:
//!
//!   1. **Patch size 16** (upstream is 14) → position-embed shape is
//!      `(1, 24*24+1, 384) = (1, 577, 384)`.
//!   2. **Windowed self-attention** in encoder layers — feature grid is
//!      partitioned into windows for local attention. See
//!      [`windowed_attn`] for partition / reverse helpers.
//!
//! The output is a feature pyramid consumed by the LWDETR encoder.

pub mod dinov2;
pub mod encoder_block;
pub mod projector;
pub mod windowed_attn;

pub use encoder_block::EncoderBlock;
pub use projector::Projector;

use mlx_rs::{fast, Array};

use crate::weights::Weights;
use crate::{Error, Result};

/// Layer indices where `run_full_attention=true`. From upstream:
///   `window_block_indexes = set(range(13)) - {3,6,9,12}`,
///   so layers in `{3, 6, 9}` (the in-range out-feature indices, i=12
///   doesn't exist) run full attention.
const FULL_ATTN_LAYERS: [usize; 3] = [3, 6, 9];

/// Layer indices AFTER which we snapshot the hidden state for the
/// multi-scale projector. Off-by-one from the config's
/// `out_feature_indexes = [3, 6, 9, 12]` because upstream prepends a
/// `"stem"` pseudo-stage to `stage_names`, so `out_feature_indexes[k]`
/// is layer `k - 1`. Verified against the ONNX graph: the post-encoder
/// layernorms consume `layer.{2,5,8,11}/Add_1_output_0`.
const COLLECT_AFTER_LAYERS: [usize; 4] = [2, 5, 8, 11];

const LAYER_NORM_EPS: f32 = 1e-6;
const NUM_LAYERS: usize = 12;
const POST_LN_W: &str = "backbone.0.encoder.encoder.layernorm.weight";
const POST_LN_B: &str = "backbone.0.encoder.encoder.layernorm.bias";

/// Full DINOv2-small encoder: 12 transformer blocks + a single shared
/// post-encoder LayerNorm applied at each multi-scale collection point.
///
/// The encoder maintains the windowed-token shape `(B*4, 145, 384)`
/// throughout — full-attention layers (3, 6, 9) reshape internally.
pub struct Encoder {
    blocks: Vec<EncoderBlock>,
    pub ln_w: Array, // shared across the 4 multi-scale outputs
    ln_b: Array,
}

impl Encoder {
    pub fn from_weights(w: &Weights) -> Result<Self> {
        let blocks = (0..NUM_LAYERS)
            .map(|i| EncoderBlock::from_weights(w, i))
            .collect::<Result<Vec<_>>>()?;
        Ok(Self {
            blocks,
            ln_w: w.get(POST_LN_W)?.deep_clone(),
            ln_b: w.get(POST_LN_B)?.deep_clone(),
        })
    }

    /// Run all 12 blocks, returning 4 LN'd multi-scale features
    /// snapshot after layers 2/5/8/11 (per `COLLECT_AFTER_LAYERS`).
    /// Each output is `(B*4, 145, 384)`.
    ///
    /// `embed_windowed` is the output of [`dinov2::Embeddings::forward`].
    pub fn forward(&self, embed_windowed: &Array) -> Result<[Array; 4]> {
        // We just rebind — no clone needed since we can shadow
        // through the loop with `let x = ...`. The first iteration
        // uses the borrowed reference, subsequent iterations the
        // freshly produced output.
        let mut x: Array = embed_windowed.clone();
        let mut collected: Vec<Option<Array>> = (0..4).map(|_| None).collect();

        // Eval cadence: too eager (every layer) blocks GPU pipelining.
        // Too lazy (none) builds a 12-block-deep graph that overflows
        // MLX's recursive eval stack. Sweet spot is to flush at every
        // collection point — this gives MLX a 2–3 layer chunk to
        // schedule, splits the graph, and matches when we'd need to
        // clone for COLLECT_AFTER_LAYERS anyway.
        for i in 0..NUM_LAYERS {
            let full_attn = FULL_ATTN_LAYERS.contains(&i);
            x = self.blocks[i].forward(&x, full_attn)?;
            if let Some(out_idx) = COLLECT_AFTER_LAYERS.iter().position(|&v| v == i) {
                collected[out_idx] = Some(x.clone());
            }
        }
        // One eval at the end — flushes the whole 12-block graph + the
        // 4 collected snapshots. MLX's CSE dedupes shared dependencies
        // across the snapshots, so each layer is computed exactly once.
        x.eval()
            .map_err(|e| Error::Inference(format!("eval encoder tail: {e}")))?;

        // Apply the shared post-encoder LayerNorm to each scale.
        let mut out: Vec<Array> = Vec::with_capacity(4);
        for (i, feat) in collected.into_iter().enumerate() {
            let f = feat.expect("each collection slot filled");
            let lnd = fast::layer_norm(&f, Some(&self.ln_w), Some(&self.ln_b), LAYER_NORM_EPS)
                .map_err(|e| Error::Inference(format!("encoder LN[{i}]: {e}")))?;
            out.push(lnd);
        }
        // Vec -> [_; 4] without Default<Array>.
        let arr: [Array; 4] = out
            .try_into()
            .map_err(|_| Error::Inference("encoder out collection length != 4".into()))?;
        Ok(arr)
    }
}

/// Full DINOv2 backbone: embeddings + windowing + 12-block encoder +
/// 4 LN'd multi-scale outputs.
pub struct Backbone {
    embeddings: dinov2::Embeddings,
    encoder: Encoder,
}

impl Backbone {
    pub fn from_weights(w: &Weights) -> Result<Self> {
        Ok(Self {
            embeddings: dinov2::Embeddings::from_weights(w)?,
            encoder: Encoder::from_weights(w)?,
        })
    }

    /// dtype of the backbone's weights (used by [`crate::RfDetr::forward`]
    /// to decide whether to cast the input).
    pub fn dtype(&self) -> mlx_rs::Dtype {
        self.encoder.ln_w.dtype()
    }

    /// Input:  `(B, 3, 384, 384)` float32 NCHW (ImageNet-normalized by caller).
    /// Output: 4 windowed feature tensors, each `(B*4, 145, 384)`,
    ///         taken at the multi-scale collection indices and
    ///         post-LN'd. Consumed by the projector.
    pub fn forward(&self, x_nchw: &Array) -> Result<[Array; 4]> {
        // No pre-encoder eval — the encoder's tail-eval flushes the
        // whole embeddings + 12-block chain in one shot.
        let windowed = self.embeddings.forward(x_nchw)?;
        self.encoder.forward(&windowed)
    }
}
