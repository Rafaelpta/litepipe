//! Enterprise install metadata.
//!
//! The real implementation lives under `ee/` (Enterprise License) and is compiled only
//! for enterprise builds. The default (non-enterprise) build reports an unmanaged,
//! consumer install.

#[cfg(feature = "enterprise-build")]
#[path = "../../../../ee/desktop-rust/enterprise_install_metadata.rs"]
pub mod inner;

#[cfg(feature = "enterprise-build")]
pub use inner::*;

// ─── Non-enterprise stub ───────────────────────────────────────────────

#[cfg(not(feature = "enterprise-build"))]
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, specta::Type)]
pub struct EnterpriseInstallMetadata {
    pub install_source: String,
    pub update_manager: String,
    pub managed: bool,
    pub detected_by: Vec<String>,
}

#[cfg(not(feature = "enterprise-build"))]
#[tauri::command]
#[specta::specta]
pub fn get_enterprise_install_metadata() -> EnterpriseInstallMetadata {
    EnterpriseInstallMetadata {
        install_source: "consumer".to_string(),
        update_manager: "screenpipe".to_string(),
        managed: false,
        detected_by: Vec::new(),
    }
}
