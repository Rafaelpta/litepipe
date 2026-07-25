//! LWDETR encoder.
//!
//! A standard transformer encoder over the multi-scale backbone features +
//! sinusoidal positional encodings. No exotic ops — port should be
//! mechanical once the backbone parity check (Phase 2) lands.

pub mod layer;
pub mod positional;

use crate::{Error, Result};

#[allow(dead_code)]
pub struct Encoder {
    _placeholder: (),
}

impl Encoder {
    pub fn forward(&self, _features: ()) -> Result<()> {
        Err(Error::NotImplemented { phase: 3 })
    }
}
