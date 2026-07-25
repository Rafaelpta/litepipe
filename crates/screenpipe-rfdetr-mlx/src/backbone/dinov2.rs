//! Patch embedding + position embeddings + cls token (DINOv2-small,
//! patch=16, hidden=384).
//!
//! The HuggingFace `Dinov2WithRegisters` initializer naming has triple
//! `encoder.encoder.encoder` nesting because RF-DETR wraps its
//! own backbone container around the HF `Dinov2Model` which itself
//! wraps a `Dinov2Encoder`. Don't try to "fix" the names — they're
//! load-bearing keys into the converted safetensors.

use mlx_rs::{ops, Array};

use crate::weights::Weights;
use crate::{Error, Result};

const HIDDEN_DIM: i32 = 384;
const PATCH_SIZE: i32 = 16;
const TOKENS_PLUS_CLS: i32 = 24 * 24 + 1;

const PATCH_W: &str = "backbone.0.encoder.encoder.embeddings.patch_embeddings.projection.weight";
const PATCH_B: &str = "backbone.0.encoder.encoder.embeddings.patch_embeddings.projection.bias";
const POS_EMBED: &str = "backbone.0.encoder.encoder.embeddings.position_embeddings";
const CLS_TOKEN: &str = "backbone.0.encoder.encoder.embeddings.cls_token";

/// Patch embedding: `Conv2d(3 → 384, kernel=16, stride=16)` with bias.
///
/// The MLX `Conv2d` op expects NHWC input and weight layout
/// `(out_channels, kH, kW, in_channels)`, while the ONNX checkpoint
/// stores NCHW + `(out, in, kH, kW)`. We transpose at construction time
/// so `forward` only does the conv + bias-add.
pub struct PatchEmbed {
    /// `(out_channels, kH, kW, in_channels) = (384, 16, 16, 3)`
    weight_nhwc: Array,
    /// `(out_channels,) = (384,)`
    bias: Array,
}

impl PatchEmbed {
    pub fn from_weights(w: &Weights) -> Result<Self> {
        let w_nchw = w.get(PATCH_W)?; // (384, 3, 16, 16)
        let weight_view = w_nchw
            .transpose_axes(&[0, 2, 3, 1])
            .map_err(|e| Error::Inference(format!("patch_embed weight transpose: {e}")))?;
        // Materialize so conv2d gets a contiguous weight tensor — saves
        // an internal copy on every forward.
        let weight_nhwc = crate::util::contiguous(&weight_view)?;
        let bias = w.get(PATCH_B)?.deep_clone();
        Ok(Self { weight_nhwc, bias })
    }

    /// Input: NCHW float32 image, `(B, 3, 384, 384)` (matching ONNX).
    /// Output: **NHWC** feature map, `(B, 24, 24, 384)`. We deliberately
    /// keep MLX's native channel-last layout instead of transposing back
    /// to NCHW — `transpose_axes` returns a strided view, and round-tripping
    /// through `as_slice()` would read storage order, not logical order.
    /// Callers (parity tests, [`Embeddings::forward`]) handle the layout
    /// difference at their boundary.
    pub fn forward(&self, x_nchw: &Array) -> Result<Array> {
        let x_nhwc = x_nchw
            .transpose_axes(&[0, 2, 3, 1])
            .map_err(|e| Error::Inference(format!("input NCHW->NHWC: {e}")))?;
        let y = ops::conv2d(
            &x_nhwc,
            &self.weight_nhwc,
            (PATCH_SIZE, PATCH_SIZE), // stride
            (0, 0),                   // padding
            (1, 1),                   // dilation
            1,                        // groups
        )
        .map_err(|e| Error::Inference(format!("patch_embed conv2d: {e}")))?;
        y.add(&self.bias)
            .map_err(|e| Error::Inference(format!("patch_embed bias add: {e}")))
    }
}

/// Number of windows per spatial dimension. RF-DETR-Nano uses
/// `num_windows=2`, so the 24×24 patch grid is split into 2×2 = 4 windows
/// of 12×12 patches each.
const NUM_WINDOWS: i32 = 2;
const PATCHES_PER_WIN: i32 = 24 / NUM_WINDOWS; // 12

/// Embeddings: patch_embed → flatten → prepend cls_token → add position
/// embeddings → window-partition → return.
///
/// Returns `(B*W², W²_window_tokens + 1, 384)` where `W²` = 4 windows
/// (cls is duplicated to each window, so each window has 145 tokens).
/// Matches the upstream `WindowedDinov2WithRegistersEmbeddings.forward`
/// output, which is the input to the encoder's first layer.
pub struct Embeddings {
    patch_embed: PatchEmbed,
    cls_token: Array, // (1, 1, 384)
    pos_embed: Array, // (1, 577, 384)
}

impl Embeddings {
    pub fn from_weights(w: &Weights) -> Result<Self> {
        Ok(Self {
            patch_embed: PatchEmbed::from_weights(w)?,
            cls_token: w.get(CLS_TOKEN)?.deep_clone(),
            pos_embed: w.get(POS_EMBED)?.deep_clone(),
        })
    }

    /// Two-stage forward, exposing the intermediate state for parity tests.
    ///
    /// Returns `(post_pos_embed, windowed)` where:
    ///   - `post_pos_embed`: `(B, 577, 384)` — cls + patches + pos
    ///   - `windowed`: `(B*4, 145, 384)` — input to the encoder
    pub fn forward_stages(&self, x_nchw: &Array) -> Result<(Array, Array)> {
        let b = x_nchw.shape()[0];
        // Patch embed: (B, 24, 24, 384) NHWC.
        let feat_nhwc = self.patch_embed.forward(x_nchw)?;
        // Flatten spatial: (B, 576, 384). Tokens are layout-agnostic.
        let tokens = feat_nhwc
            .reshape(&[b, 24 * 24, HIDDEN_DIM])
            .map_err(|e| Error::Inference(format!("patch flatten: {e}")))?;
        // Prepend cls token. (1, 1, 384) broadcasts on concat for B>1
        // through MLX's broadcasting rules — explicit broadcast for safety.
        let cls = if b == 1 {
            self.cls_token.clone()
        } else {
            ops::broadcast_to(&self.cls_token, &[b, 1, HIDDEN_DIM])
                .map_err(|e| Error::Inference(format!("cls broadcast: {e}")))?
        };
        let with_cls = ops::concatenate_axis(&[&cls, &tokens], 1)
            .map_err(|e| Error::Inference(format!("cls concat: {e}")))?;
        // Add position embeddings. pos_embed is (1, 577, 384), broadcasts.
        let post_pos = with_cls
            .add(&self.pos_embed)
            .map_err(|e| Error::Inference(format!("pos add: {e}")))?;
        debug_assert_eq!(post_pos.shape(), &[b, TOKENS_PLUS_CLS, HIDDEN_DIM]);

        // Window partition. Split off cls (axis=1, position 0) and patches (rest).
        let parts = ops::split_sections(&post_pos, &[1], 1)
            .map_err(|e| Error::Inference(format!("cls/patches split: {e}")))?;
        debug_assert_eq!(parts.len(), 2);
        let cls_with_pos = &parts[0]; // (B, 1, 384)
        let patches_with_pos = &parts[1]; // (B, 576, 384)

        // (B, 576, 384) -> (B*W, H_in, W, W_in, C) via reshape (memory unchanged).
        // For B=1, W=2, H_in=12, W_in=12: (2, 12, 2, 12, 384).
        // First reshape inflates batch by W (= num_h_windows),
        // grouping rows into window-rows.
        let windowed_a = patches_with_pos
            .reshape(&[
                b * NUM_WINDOWS,
                PATCHES_PER_WIN,
                NUM_WINDOWS,
                PATCHES_PER_WIN,
                HIDDEN_DIM,
            ])
            .map_err(|e| Error::Inference(format!("window reshape #1: {e}")))?;
        // Permute so window dims are adjacent to batch: (B*W, W, H_in, W_in, C).
        let windowed_b = windowed_a
            .transpose_axes(&[0, 2, 1, 3, 4])
            .map_err(|e| Error::Inference(format!("window permute: {e}")))?;
        // Collapse to (B*W*W, H_in*W_in, C) = (B*4, 144, 384).
        let windowed_c = windowed_b
            .reshape(&[
                b * NUM_WINDOWS * NUM_WINDOWS,
                PATCHES_PER_WIN * PATCHES_PER_WIN,
                HIDDEN_DIM,
            ])
            .map_err(|e| Error::Inference(format!("window reshape #2: {e}")))?;

        // Replicate cls 4 times along batch.
        let n_win = NUM_WINDOWS * NUM_WINDOWS; // 4
        let cls_replicated = ops::tile(cls_with_pos, &[n_win, 1, 1])
            .map_err(|e| Error::Inference(format!("cls tile: {e}")))?;

        // Concat cls + windowed along seq axis → (B*4, 145, 384).
        let windowed = ops::concatenate_axis(&[&cls_replicated, &windowed_c], 1)
            .map_err(|e| Error::Inference(format!("windowed concat: {e}")))?;

        Ok((post_pos, windowed))
    }

    /// Returns just the windowed embedding (encoder input).
    pub fn forward(&self, x_nchw: &Array) -> Result<Array> {
        Ok(self.forward_stages(x_nchw)?.1)
    }
}
