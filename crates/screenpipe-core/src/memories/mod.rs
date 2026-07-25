//! Memories — cross-device sync types.
//!
//! The persistence layer (sqlite, FTS, queries) lives in `screenpipe-db`;
//! this module hosts only what other crates and the cloud sync stack need:
//! the over-the-wire manifest format and the LWW merge function.

#[cfg(feature = "cloud-sync")]
pub mod sync;

pub mod external_sync;
