use thiserror::Error;

pub type VaultResult<T> = Result<T, VaultError>;

#[derive(Debug, Error)]
pub enum VaultError {
    #[error("vault is not set up — run setup first")]
    NotSetUp,

    #[error("vault is already locked")]
    AlreadyLocked,

    #[error("vault is already unlocked")]
    AlreadyUnlocked,

    #[error("wrong password")]
    WrongPassword,

    #[error("crypto error: {0}")]
    Crypto(String),

    #[error("io error: {0}")]
    Io(#[from] std::io::Error),

    #[error("{0}")]
    Other(String),
}
