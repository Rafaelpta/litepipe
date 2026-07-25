//! Power management — battery-aware capture parameter adjustment.
//!
//! This module polls battery/thermal state, selects a power profile
//! (Performance / Balanced / Saver), and broadcasts parameter changes
//! to vision and audio subsystems via a `tokio::sync::watch` channel.
//!
//! # Architecture
//!
//! ```text
//! monitor.rs  — polls OS for battery %, AC state, thermal pressure
//! profile.rs  — defines three parameter bundles + selection logic
//! manager.rs  — coordinator loop: poll → select profile → broadcast
//! ```

pub mod manager;
pub mod monitor;
pub mod profile;

// Re-export the public API at the module level
pub use manager::{
    start_power_manager, start_power_manager_with_pref, PowerManagerHandle, PowerStatus,
};
pub use monitor::{PowerState, ThermalState};
pub use profile::{PowerMode, PowerProfile, ProfileName};
