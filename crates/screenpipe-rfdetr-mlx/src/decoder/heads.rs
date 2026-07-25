//! Per-query classification + bbox-regression heads.

use crate::{Error, Result};

/// `class_head`: `Linear(dim → num_classes)`. RF-DETR uses 13 outputs
/// (12 PII classes + no-object). Output is logits, sigmoid'd in
/// postprocess.
pub struct ClassificationHead;

impl ClassificationHead {
    pub fn forward(&self, _hs: ()) -> Result<()> {
        Err(Error::NotImplemented { phase: 5 })
    }
}

/// `bbox_head`: 3-layer MLP (`dim → dim → dim → 4`) producing
/// `(cx, cy, w, h)` deltas added to the per-layer reference points.
pub struct BBoxHead;

impl BBoxHead {
    pub fn forward(&self, _hs: ()) -> Result<()> {
        Err(Error::NotImplemented { phase: 5 })
    }
}
