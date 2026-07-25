//! Single decoder layer: self-attn → cross-attn (deformable) → FFN, pre-norm.

use crate::{Error, Result};

#[allow(dead_code)]
pub struct DecoderLayer {
    _placeholder: (),
}

impl DecoderLayer {
    pub fn forward(
        &self,
        _tgt: (),
        _query_pos: (),
        _ref_points: (),
        _memory: (),
        _spatial_shapes: (),
        _level_start_index: (),
    ) -> Result<()> {
        Err(Error::NotImplemented { phase: 5 })
    }
}
