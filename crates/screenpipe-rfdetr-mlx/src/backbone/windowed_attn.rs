//! Window partitioning for RF-DETR's windowed self-attention.
//!
//! RF-DETR breaks the `H × W` feature grid into `(H/win) × (W/win)` windows
//! of size `win × win`, runs self-attention inside each window only, then
//! reverses the partition. This makes the backbone O(N) on tokens-per-window
//! instead of O(N²) on the full grid.
//!
//! Window size for RF-DETR-Nano @ 384 input: `win = 16` for the early
//! blocks, full attention for the last 2 blocks. Confirm exact schedule
//! against `rfdetr/models/backbone.py::DinoV2Encoder` when porting.

use crate::{Error, Result};

/// Partition `(B, H, W, C)` into `(B * num_windows, win, win, C)`.
pub fn window_partition(_x: (), _win: usize) -> Result<()> {
    Err(Error::NotImplemented { phase: 2 })
}

/// Reverse [`window_partition`].
pub fn window_reverse(_x: (), _win: usize, _h: usize, _w: usize) -> Result<()> {
    Err(Error::NotImplemented { phase: 2 })
}
