//! 300 learned object queries + their reference-point initialization.

use crate::{Error, Result};

#[allow(dead_code)]
pub struct ObjectQueries {
    /// `(num_queries, dim)` learned content vectors.
    _content: (),
    /// `(num_queries, 4)` learned reference (cx, cy, w, h) — sigmoid'd at use.
    _ref_anchor: (),
}

impl ObjectQueries {
    pub fn build(_num_queries: usize) -> Result<Self> {
        Err(Error::NotImplemented { phase: 5 })
    }
}
