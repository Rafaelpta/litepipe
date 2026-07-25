//! Shared screen-lock state for cross-crate coordination.
//!
//! The sleep monitor (in `screenpipe-engine`) writes to this flag via
//! [`set_screen_locked`]. Consumer crates (e.g. `screenpipe-audio`) read it
//! via [`screen_is_locked`] to skip work while the screen is locked.
//!
//! The `record_while_locked` flag is set by the config/UI layer and read by
//! the audio recording loop to decide whether to pause during lock.

use std::sync::atomic::{AtomicBool, Ordering};

/// Whether the screen is currently locked / screensaver active.
static SCREEN_IS_LOCKED: AtomicBool = AtomicBool::new(false);

/// Whether to continue recording audio while the screen is locked.
/// Default: false (audio pauses when locked).
static RECORD_WHILE_LOCKED: AtomicBool = AtomicBool::new(false);

/// Returns `true` if the screen is currently locked or showing the screensaver.
pub fn screen_is_locked() -> bool {
    SCREEN_IS_LOCKED.load(Ordering::SeqCst)
}

/// Set the shared screen-lock flag. Called by the sleep monitor.
pub fn set_screen_locked(locked: bool) {
    SCREEN_IS_LOCKED.store(locked, Ordering::SeqCst);
}

/// Returns `true` if audio recording should continue while the screen is locked.
pub fn record_while_locked() -> bool {
    RECORD_WHILE_LOCKED.load(Ordering::SeqCst)
}

/// Set the record-while-locked preference. Called when config changes.
pub fn set_record_while_locked(enabled: bool) {
    RECORD_WHILE_LOCKED.store(enabled, Ordering::SeqCst);
}

/// Returns `true` if audio should be paused right now due to screen lock.
/// Convenience: locked AND not configured to record while locked.
pub fn should_pause_audio_for_lock() -> bool {
    screen_is_locked() && !record_while_locked()
}
