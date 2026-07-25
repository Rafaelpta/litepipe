//! Vault encryption for screenpipe data at rest.
//!
//! Provides lock/unlock lifecycle for encrypting all screenpipe data
//! (database, screenshots, audio) when the user intentionally locks.
//!
//! # Usage
//! ```ignore
//! use screenpipe_vault::VaultManager;
//!
//! # async fn example() -> anyhow::Result<()> {
//! let vault = VaultManager::new(screenpipe_core::paths::default_screenpipe_data_dir());
//! vault.setup("my-password").await?;
//! vault.lock("my-password").await?;
//! vault.unlock("my-password").await?;
//! # Ok(())
//! # }
//! ```

pub mod crypto;
pub mod error;
pub mod manager;
pub mod migration;

pub use error::{VaultError, VaultResult};
pub use manager::{VaultManager, VaultState};
