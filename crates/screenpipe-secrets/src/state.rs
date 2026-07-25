//! Whether the user has opted into secret-store encryption.
//!
//! Single source of truth so the app, the engine binary, and the permission
//! monitor all agree on whether the keychain should be touched. Read-only —
//! never accesses the keychain itself.

use std::path::Path;

const FLAG_FILENAME: &str = ".encrypt-store";
const STORE_FILENAME: &str = "store.bin";
const STORE_MAGIC: &[u8; 8] = b"SPSTORE1";

/// Returns true when the user has opted into encryption, by ANY of:
/// - `SCREENPIPE_ENCRYPT_STORE=1` env var (testing/override)
/// - `<data_dir>/.encrypt-store` flag file exists
/// - `<data_dir>/store.bin` is encrypted (`SPSTORE1` magic)
/// - `<data_dir>/store.bin` is plain JSON with `settings.encryptStore == true`
pub fn is_encryption_requested(data_dir: &Path) -> bool {
    if std::env::var("SCREENPIPE_ENCRYPT_STORE").is_ok_and(|v| v == "1") {
        return true;
    }
    if data_dir.join(FLAG_FILENAME).exists() {
        return true;
    }
    let Ok(data) = std::fs::read(data_dir.join(STORE_FILENAME)) else {
        return false;
    };
    if data.len() >= STORE_MAGIC.len() && &data[..STORE_MAGIC.len()] == STORE_MAGIC {
        return true;
    }
    serde_json::from_slice::<serde_json::Value>(&data)
        .ok()
        .and_then(|json| {
            json.get("settings")
                .and_then(|s| s.get("encryptStore"))
                .and_then(|v| v.as_bool())
        })
        .unwrap_or(false)
}

/// Mark encryption as opted in. Call AFTER a keychain key has been created.
pub fn mark_encryption_enabled(data_dir: &Path) -> std::io::Result<()> {
    std::fs::write(data_dir.join(FLAG_FILENAME), b"")
}

/// Mark encryption as opted out. Idempotent — succeeds if the flag was already
/// absent. Caller is responsible for deleting the keychain key separately.
pub fn mark_encryption_disabled(data_dir: &Path) -> std::io::Result<()> {
    match std::fs::remove_file(data_dir.join(FLAG_FILENAME)) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    #[test]
    fn flag_file_signals_enabled() {
        let dir = TempDir::new().unwrap();
        assert!(!is_encryption_requested(dir.path()));
        mark_encryption_enabled(dir.path()).unwrap();
        assert!(is_encryption_requested(dir.path()));
        mark_encryption_disabled(dir.path()).unwrap();
        assert!(!is_encryption_requested(dir.path()));
    }

    #[test]
    fn encrypted_store_magic_signals_enabled() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join(STORE_FILENAME), b"SPSTORE1\x00\x00\x00").unwrap();
        assert!(is_encryption_requested(dir.path()));
    }

    #[test]
    fn settings_json_signals_enabled() {
        let dir = TempDir::new().unwrap();
        fs::write(
            dir.path().join(STORE_FILENAME),
            br#"{"settings":{"encryptStore":true}}"#,
        )
        .unwrap();
        assert!(is_encryption_requested(dir.path()));

        fs::write(
            dir.path().join(STORE_FILENAME),
            br#"{"settings":{"encryptStore":false}}"#,
        )
        .unwrap();
        assert!(!is_encryption_requested(dir.path()));
    }

    #[test]
    fn disable_is_idempotent() {
        let dir = TempDir::new().unwrap();
        mark_encryption_disabled(dir.path()).unwrap();
        mark_encryption_disabled(dir.path()).unwrap();
    }
}
