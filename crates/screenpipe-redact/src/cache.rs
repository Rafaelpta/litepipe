//! SHA-256 keyed cache for redaction results.
//!
//! Screenpipe captures repeat enormously: the same window title /
//! accessibility tree / OCR strip can show up hundreds of times per
//! session as the user moves between apps. Caching at the (text,
//! redactor_version) granularity typically gets a 70-90% hit rate on
//! a workday's worth of data, which is the difference between sending
//! 10k strings to a remote enclave per hour and sending ~1k.

use std::sync::Arc;
use std::time::Duration;

use moka::future::Cache;
use sha2::{Digest, Sha256};

use crate::RedactionOutput;

/// Default capacity. ~10 KiB per entry → ~30 MiB at full size. Cheap.
pub const DEFAULT_CAPACITY: u64 = 4_096;

/// Default TTL. Output is deterministic for fixed (text, version) so
/// TTL exists only to bound memory footprint over a long session.
pub const DEFAULT_TTL: Duration = Duration::from_secs(60 * 60);

/// Cache key — SHA256(text || redactor_name || redactor_version).
/// Prefix-binding to the redactor identity prevents cross-contamination
/// when the user switches between adapters.
pub fn cache_key(text: &str, redactor_name: &str, redactor_version: u32) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(text.as_bytes());
    h.update(b"\x00");
    h.update(redactor_name.as_bytes());
    h.update(b"\x00");
    h.update(redactor_version.to_le_bytes());
    h.finalize().into()
}

/// Wrapper so the underlying moka::Cache type doesn't leak through
/// the public API.
pub(crate) struct RedactionCache {
    inner: Cache<[u8; 32], Arc<RedactionOutput>>,
}

impl RedactionCache {
    pub fn new(capacity: u64, ttl: Duration) -> Self {
        Self {
            inner: Cache::builder()
                .max_capacity(capacity)
                .time_to_live(ttl)
                .build(),
        }
    }

    pub fn with_defaults() -> Self {
        Self::new(DEFAULT_CAPACITY, DEFAULT_TTL)
    }

    pub async fn get(&self, key: &[u8; 32]) -> Option<Arc<RedactionOutput>> {
        self.inner.get(key).await
    }

    pub async fn insert(&self, key: [u8; 32], value: RedactionOutput) -> Arc<RedactionOutput> {
        let arc = Arc::new(value);
        self.inner.insert(key, arc.clone()).await;
        arc
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cache_key_changes_with_text() {
        let a = cache_key("hello", "x", 1);
        let b = cache_key("HELLO", "x", 1);
        assert_ne!(a, b);
    }

    #[test]
    fn cache_key_changes_with_redactor_name() {
        let a = cache_key("hello", "regex", 1);
        let b = cache_key("hello", "tinfoil", 1);
        assert_ne!(a, b);
    }

    #[test]
    fn cache_key_changes_with_version() {
        let a = cache_key("hello", "regex", 1);
        let b = cache_key("hello", "regex", 2);
        assert_ne!(a, b);
    }
}
