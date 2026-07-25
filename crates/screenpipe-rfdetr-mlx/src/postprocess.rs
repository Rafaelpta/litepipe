//! sigmoid → top-k → bbox-decode → [`crate::Detection`].

use crate::{Detection, Error, Result};

/// Final stage of inference. Mirrors
/// `rfdetr/models/lwdetr.py::PostProcess` exactly.
///
/// - Apply sigmoid to per-query logits
/// - Take top-k (k=300) flattened across (queries × classes)
/// - Map back to query-idx + class-idx
/// - Decode `(cx, cy, w, h)` (normalized) → `(x, y, w, h)` in image pixels
/// - Filter by `score_threshold`
pub fn postprocess(
    _logits: (),
    _boxes: (),
    _orig_w: u32,
    _orig_h: u32,
    _score_threshold: f32,
    _topk: usize,
) -> Result<Vec<Detection>> {
    Err(Error::NotImplemented { phase: 6 })
}
