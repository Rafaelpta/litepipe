//! Sine-cosine position encoding for 2D feature maps (DETR-style).

use crate::{Error, Result};

/// `(B, H, W) -> (B, C, H, W)` where the last dim is interleaved sin/cos
/// across the spatial axes. `C = num_pos_feats * 2`. Default
/// `num_pos_feats = 128` → `C = 256`.
pub fn sine_pos_embed(_b: usize, _h: usize, _w: usize, _num_pos_feats: usize) -> Result<()> {
    Err(Error::NotImplemented { phase: 3 })
}
