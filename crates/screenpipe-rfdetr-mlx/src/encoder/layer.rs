//! Single transformer encoder layer: self-attn → FFN, both pre-norm.

use crate::{Error, Result};

#[allow(dead_code)]
pub struct EncoderLayer {
    _placeholder: (),
}

impl EncoderLayer {
    pub fn forward(&self, _src: (), _pos: ()) -> Result<()> {
        Err(Error::NotImplemented { phase: 3 })
    }
}
