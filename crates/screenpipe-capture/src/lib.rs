//! Paired screenshot + accessibility-tree capture, persisted to the screenpipe DB.
//!
//! Extracted from `screenpipe-engine` so that both the engine binary and the
//! `screenpipe-sdk` napi addon can run the same capture pipeline without the
//! SDK pulling the engine's full dependency tree (audio, axum server, secrets,
//! etc.).
//!
//! The capture function — [`paired_capture::paired_capture`] — takes a
//! [`paired_capture::CaptureContext`] (DB handle + snapshot writer + the image
//! to process) and writes a frame row with accessibility text plus a JPEG
//! snapshot to disk. Callers own the *trigger* (1 Hz tick, event-driven,
//! cron — doesn't matter to this crate).

pub mod paired_capture;

pub use paired_capture::{
    paired_capture, walk_accessibility_tree, CaptureContext, PairedCaptureResult,
};
