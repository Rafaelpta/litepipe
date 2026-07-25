//! Unified credential store for screenpipe.
//!
//! All secrets (OAuth tokens, API keys, session data) are stored in a single
//! `secrets` table in the main SQLite database, encrypted with AES-256-GCM.
//! The encryption key lives in the OS keychain.

mod crypto;
pub mod keychain;
mod migration;
mod state;
mod store;

pub use migration::{fix_secret_file_permissions, migrate_legacy_secrets, MigrationReport};
pub use state::{is_encryption_requested, mark_encryption_disabled, mark_encryption_enabled};
pub use store::SecretStore;
