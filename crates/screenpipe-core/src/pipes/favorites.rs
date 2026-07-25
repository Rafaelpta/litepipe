//! Pipe favorites — local per-machine list of pipe names the user has starred.
//!
//! Stored as JSON at `<pipes_dir>/favorites.json` to match the existing
//! sibling files (`tombstones.json`, `local-overrides.json`). Atomic writes
//! via tempfile + rename. Order is deduplicated but otherwise preserved so
//! the UI can show newest favorites last if it wants to.
//!
//! This is deliberately *not* synced to the cloud — it's a UI preference,
//! not pipe state. If users want cross-device favorites later, folding this
//! file into `cloud-sync` is a one-liner.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::{Path, PathBuf};

pub const FAVORITES_FILE: &str = "favorites.json";
const TMP_FILE: &str = ".favorites.json.tmp";

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct FavoritesFile {
    /// Pipe names (same IDs as `list_pipes` returns) the user has starred.
    /// Order is preserved — callers may use it to sort "recently starred".
    pub favorites: Vec<String>,
}

fn path(pipes_dir: &Path) -> PathBuf {
    pipes_dir.join(FAVORITES_FILE)
}

/// Read the favorites file. Returns an empty list if the file is absent or
/// malformed — favorites is a pure preference, never block pipe listing on
/// it. Callers should not need to handle I/O errors.
pub fn load(pipes_dir: &Path) -> Vec<String> {
    let p = path(pipes_dir);
    let raw = match std::fs::read_to_string(&p) {
        Ok(r) => r,
        Err(_) => return Vec::new(),
    };
    match serde_json::from_str::<FavoritesFile>(&raw) {
        Ok(f) => dedup_preserve(f.favorites),
        Err(e) => {
            tracing::warn!(
                "favorites.json at {} is malformed, treating as empty: {}",
                p.display(),
                e
            );
            Vec::new()
        }
    }
}

/// Replace the whole favorites list atomically. Duplicate entries in the
/// input are collapsed but order is preserved.
pub fn save(pipes_dir: &Path, favorites: &[String]) -> Result<()> {
    let deduped = dedup_preserve(favorites.to_vec());
    let file = FavoritesFile { favorites: deduped };
    let final_path = path(pipes_dir);
    let tmp_path = pipes_dir.join(TMP_FILE);

    if let Some(parent) = final_path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("creating parent dir for {}", final_path.display()))?;
    }

    let json = serde_json::to_string_pretty(&file)?;
    std::fs::write(&tmp_path, json)
        .with_context(|| format!("writing favorites tempfile at {}", tmp_path.display()))?;
    std::fs::rename(&tmp_path, &final_path)
        .with_context(|| format!("renaming {} → {}", tmp_path.display(), final_path.display()))?;
    Ok(())
}

/// Mark `pipe` as favorite (idempotent — adding an already-favorite pipe
/// is a no-op). Returns the new full list.
pub fn add(pipes_dir: &Path, pipe: &str) -> Result<Vec<String>> {
    let mut list = load(pipes_dir);
    if !list.iter().any(|n| n == pipe) {
        list.push(pipe.to_string());
    }
    save(pipes_dir, &list)?;
    Ok(list)
}

/// Remove `pipe` from favorites. Returns the new full list. Never errors
/// when the pipe wasn't favorited — call site doesn't need to check first.
pub fn remove(pipes_dir: &Path, pipe: &str) -> Result<Vec<String>> {
    let mut list = load(pipes_dir);
    list.retain(|n| n != pipe);
    save(pipes_dir, &list)?;
    Ok(list)
}

/// Toggle `pipe`'s favorite status to `favorite`. Idempotent.
pub fn set(pipes_dir: &Path, pipe: &str, favorite: bool) -> Result<Vec<String>> {
    if favorite {
        add(pipes_dir, pipe)
    } else {
        remove(pipes_dir, pipe)
    }
}

/// Membership test without loading into a HashSet in the caller.
pub fn is_favorite(pipes_dir: &Path, pipe: &str) -> bool {
    load(pipes_dir).iter().any(|n| n == pipe)
}

/// Fast HashSet view — use when checking many pipes at once (e.g. the
/// `list_pipes` handler annotating results).
pub fn as_set(pipes_dir: &Path) -> HashSet<String> {
    load(pipes_dir).into_iter().collect()
}

fn dedup_preserve(input: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut out = Vec::with_capacity(input.len());
    for name in input {
        if seen.insert(name.clone()) {
            out.push(name);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmpdir() -> tempfile::TempDir {
        tempfile::tempdir().expect("tempdir")
    }

    #[test]
    fn load_empty_when_file_missing() {
        let d = tmpdir();
        assert!(load(d.path()).is_empty());
    }

    #[test]
    fn save_then_load_roundtrip() {
        let d = tmpdir();
        save(d.path(), &["a".into(), "b".into(), "c".into()]).unwrap();
        assert_eq!(load(d.path()), vec!["a", "b", "c"]);
    }

    #[test]
    fn add_is_idempotent() {
        let d = tmpdir();
        add(d.path(), "foo").unwrap();
        add(d.path(), "foo").unwrap();
        add(d.path(), "foo").unwrap();
        assert_eq!(load(d.path()), vec!["foo"]);
    }

    #[test]
    fn add_preserves_insertion_order() {
        let d = tmpdir();
        add(d.path(), "first").unwrap();
        add(d.path(), "second").unwrap();
        add(d.path(), "third").unwrap();
        assert_eq!(load(d.path()), vec!["first", "second", "third"]);
    }

    #[test]
    fn remove_nonexistent_is_noop() {
        let d = tmpdir();
        add(d.path(), "foo").unwrap();
        remove(d.path(), "never-added").unwrap();
        assert_eq!(load(d.path()), vec!["foo"]);
    }

    #[test]
    fn remove_then_readd_moves_to_end() {
        let d = tmpdir();
        for n in ["a", "b", "c"] {
            add(d.path(), n).unwrap();
        }
        remove(d.path(), "b").unwrap();
        add(d.path(), "b").unwrap();
        assert_eq!(load(d.path()), vec!["a", "c", "b"]);
    }

    #[test]
    fn set_true_adds_set_false_removes() {
        let d = tmpdir();
        set(d.path(), "x", true).unwrap();
        assert!(is_favorite(d.path(), "x"));
        set(d.path(), "x", false).unwrap();
        assert!(!is_favorite(d.path(), "x"));
    }

    #[test]
    fn set_is_idempotent() {
        let d = tmpdir();
        set(d.path(), "x", true).unwrap();
        set(d.path(), "x", true).unwrap();
        set(d.path(), "x", false).unwrap();
        set(d.path(), "x", false).unwrap();
        assert_eq!(load(d.path()), Vec::<String>::new());
    }

    #[test]
    fn as_set_matches_load() {
        let d = tmpdir();
        add(d.path(), "a").unwrap();
        add(d.path(), "b").unwrap();
        let s = as_set(d.path());
        assert_eq!(s.len(), 2);
        assert!(s.contains("a"));
        assert!(s.contains("b"));
    }

    #[test]
    fn save_dedupes_input() {
        let d = tmpdir();
        // A caller passes duplicates — we collapse but keep first-seen order.
        save(
            d.path(),
            &["a".into(), "b".into(), "a".into(), "c".into(), "b".into()],
        )
        .unwrap();
        assert_eq!(load(d.path()), vec!["a", "b", "c"]);
    }

    #[test]
    fn malformed_file_returns_empty_list() {
        let d = tmpdir();
        std::fs::write(d.path().join(FAVORITES_FILE), "not json at all").unwrap();
        assert!(load(d.path()).is_empty());
    }

    #[test]
    fn save_overwrites_previous() {
        let d = tmpdir();
        save(d.path(), &["a".into(), "b".into()]).unwrap();
        save(d.path(), &["x".into()]).unwrap();
        assert_eq!(load(d.path()), vec!["x"]);
    }

    #[test]
    fn save_writes_via_tempfile_no_leftover() {
        let d = tmpdir();
        save(d.path(), &["a".into()]).unwrap();
        // Temp file must not linger after a successful save.
        assert!(!d.path().join(TMP_FILE).exists());
    }
}
