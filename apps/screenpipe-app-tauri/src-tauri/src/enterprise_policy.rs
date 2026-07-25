//! Enterprise policy.
//!
//! The real implementation lives under `ee/` (Enterprise License) and is compiled only
//! for enterprise builds. The default (non-enterprise) build uses the permissive stubs
//! below: nothing is hidden and the policy setters are no-ops.

#[cfg(feature = "enterprise-build")]
#[path = "../../../../ee/desktop-rust/enterprise_policy.rs"]
pub mod inner;

#[cfg(feature = "enterprise-build")]
pub use inner::*;

// ─── Non-enterprise stubs ──────────────────────────────────────────────

#[cfg(not(feature = "enterprise-build"))]
pub fn is_app_ui_hidden() -> bool {
    false
}

#[cfg(not(feature = "enterprise-build"))]
pub fn is_tray_item_hidden(_item: &str) -> bool {
    false
}

#[cfg(not(feature = "enterprise-build"))]
#[tauri::command]
#[specta::specta]
#[allow(unused_variables)]
pub fn set_enterprise_policy(hidden_sections: Vec<String>) {}

#[cfg(not(feature = "enterprise-build"))]
#[tauri::command]
#[specta::specta]
#[allow(unused_variables)]
pub fn set_sync_streams(
    frames: bool,
    audio: bool,
    ui_events: bool,
    memories: bool,
    snapshots: bool,
) {
}
