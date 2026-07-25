//! Legacy embedded server module — superseded by [`server_core`] + [`capture_session`].
//!
//! The monolithic `start_embedded_server` function has been split into:
//! - `server_core::ServerCore` — long-lived: DB, HTTP server, pipes, secrets.
//! - `capture_session::CaptureSession` — short-lived: vision, audio, UI recording.
//!
//! This module is kept as a placeholder to avoid breaking `mod embedded_server`
//! declarations. It will be removed in a future cleanup.
