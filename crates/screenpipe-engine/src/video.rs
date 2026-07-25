//! Re-export of the encoder helpers. The real implementation lives in
//! `screenpipe_core::video` now so downstream consumers (the commercial
//! `@screenpipe/sdk`) can use the same x265 pipeline without pulling the
//! engine's full dep tree. Internal callers here
//! (`snapshot_compaction`, `routes::frames`) keep the old
//! `screenpipe_engine::video::*` import path thanks to this re-export.

pub use screenpipe_core::video::*;
