//! Pipe lifecycle events.
//!
//! Emitted when a pipe finishes execution so other pipes can chain off it
//! via `trigger.events: ["pipe_completed:pipe-name"]`.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Emitted to the event bus as `"pipe_completed:{pipe_name}"` when a pipe
/// finishes executing (success or failure).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PipeCompletedEvent {
    pub pipe_name: String,
    pub success: bool,
    pub duration_secs: f64,
    pub timestamp: DateTime<Utc>,
}
