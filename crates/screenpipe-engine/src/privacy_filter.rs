//! Thin client around the Tinfoil-hosted `openai/privacy-filter` service.
//!
//! Called from the `/search` handler when the request sets `filter_pii=true`
//! so every text-bearing field (OCR text, audio transcription, UI text,
//! memory content) gets PII redacted before leaving the user's device.
//!
//! Design notes:
//! - Tinfoil SDK does AMD SEV-SNP attestation + Sigstore code-provenance
//!   verification + TLS certificate pinning at first use. This proves the
//!   enclave is running the exact open-source build at
//!   github.com/screenpipe/privacy-filter and pins TLS to the attested key,
//!   so a MITM or compromised CA can't observe unredacted text in transit.
//! - Lazy async init (tokio OnceCell): the verifying handshake (~1-2s on
//!   first call) is paid once, then reqwest connection-pools the rest.
//! - Per-text SHA256 LRU cache. Screen content repeats constantly (chrome
//!   tabs, IDE panes, the same email thread) — caching typically cuts the
//!   Tinfoil round-trip count by 5-10× during an active session.
//! - Empty / tiny text is returned unchanged to avoid wasteful calls.
//! - Parallel `filter_batch` is a `try_join_all` over individual calls; the
//!   enclave saturates around 8 concurrent requests so we don't need
//!   finer-grained batching yet.
//! - Fails closed: the caller (search handler) turns any error into an HTTP
//!   error so unredacted text never slips through silently. An attestation
//!   failure (network down, measurement mismatch) therefore blocks the
//!   filter rather than falling back to plain TLS.

use std::sync::Arc;
use std::time::Duration;

use moka::future::Cache;
use once_cell::sync::OnceCell;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::sync::OnceCell as AsyncOnceCell;

/// Minimum text length worth sending through the filter. Below this we
/// assume the text can't contain meaningful PII and skip the round-trip.
const MIN_FILTER_CHARS: usize = 8;

/// Cache size — tuned for ~20 results per search × ~50 recent queries.
const CACHE_CAPACITY: u64 = 2_000;

/// How long a cached redaction stays valid. The model output is
/// deterministic for a given input so TTL only exists to bound memory.
const CACHE_TTL: Duration = Duration::from_secs(60 * 60);

/// Enclave host pinned to our deployed Tinfoil container.
const DEFAULT_ENCLAVE: &str = "pii.screenpipe.containers.tinfoil.dev";
/// GitHub repo whose Sigstore-attested release measurement must match the
/// running enclave (Step 2/3 of Tinfoil's verification).
const DEFAULT_REPO: &str = "screenpipe/privacy-filter";

#[derive(Debug)]
pub enum FilterError {
    Request(reqwest::Error),
    Status(reqwest::StatusCode),
    Attestation(String),
}

impl std::fmt::Display for FilterError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FilterError::Request(e) => write!(f, "privacy filter request failed: {}", e),
            FilterError::Status(s) => write!(f, "privacy filter returned status: {}", s),
            FilterError::Attestation(e) => write!(f, "privacy filter attestation failed: {}", e),
        }
    }
}

impl std::error::Error for FilterError {}

impl From<reqwest::Error> for FilterError {
    fn from(e: reqwest::Error) -> Self {
        FilterError::Request(e)
    }
}

#[derive(Serialize)]
struct FilterRequest<'a> {
    text: &'a str,
    include_spans: bool,
}

#[derive(Deserialize)]
struct FilterResponse {
    redacted: String,
}

pub struct PrivacyFilter {
    enclave: String,
    repo: String,
    /// Built lazily on first `filter()` call so attestation cost (~1-2s
    /// hardware-attestation + Sigstore + cert-pinning) doesn't fire at
    /// engine startup for users who never enable PII filtering.
    client: AsyncOnceCell<tinfoil::Client>,
    cache: Cache<[u8; 32], Arc<String>>,
}

impl PrivacyFilter {
    fn new(enclave: String, repo: String) -> Self {
        let cache = Cache::builder()
            .max_capacity(CACHE_CAPACITY)
            .time_to_live(CACHE_TTL)
            .build();

        Self {
            enclave,
            repo,
            client: AsyncOnceCell::new(),
            cache,
        }
    }

    /// Verify the enclave + return its attested HTTP client. The Tinfoil SDK
    /// does the AMD SEV-SNP attestation, Sigstore signature check, and
    /// measurement comparison all inside `Client::new`; we cache the result
    /// so subsequent calls reuse the verified connection pool.
    async fn http(&self) -> Result<&reqwest::Client, FilterError> {
        let client = self
            .client
            .get_or_try_init(|| async {
                // The privacy-filter container itself doesn't enforce a
                // bearer token (its /filter endpoint is open inside the
                // attested enclave), so the api_key here is just a
                // placeholder for the SDK constructor.
                tinfoil::Client::new(&self.enclave, &self.repo, "")
                    .await
                    .map_err(|e| FilterError::Attestation(e.to_string()))
            })
            .await?;
        client
            .http_client()
            .map_err(|e| FilterError::Attestation(e.to_string()))
    }

    /// Redact a single text. Returns the original unchanged if it's shorter
    /// than `MIN_FILTER_CHARS`. Caches successful redactions by SHA256.
    pub async fn filter(&self, text: &str) -> Result<String, FilterError> {
        if text.chars().count() < MIN_FILTER_CHARS {
            return Ok(text.to_string());
        }

        let mut hasher = Sha256::new();
        hasher.update(text.as_bytes());
        let key: [u8; 32] = hasher.finalize().into();

        if let Some(cached) = self.cache.get(&key).await {
            return Ok((*cached).clone());
        }

        let http = self.http().await?;
        let resp = http
            .post(format!("https://{}/filter", self.enclave))
            .timeout(Duration::from_secs(5))
            .json(&FilterRequest {
                text,
                include_spans: false,
            })
            .send()
            .await?;

        if !resp.status().is_success() {
            return Err(FilterError::Status(resp.status()));
        }

        let parsed: FilterResponse = resp.json().await?;
        let redacted = Arc::new(parsed.redacted);
        self.cache.insert(key, redacted.clone()).await;
        Ok((*redacted).clone())
    }

    /// Redact a batch of texts in parallel. Preserves input order.
    /// Any single failure fails the whole batch — caller should surface
    /// a 503 so the client never sees partially-redacted results.
    pub async fn filter_batch(&self, texts: Vec<String>) -> Result<Vec<String>, FilterError> {
        let futures = texts.into_iter().map(|t| async move {
            let out = self.filter(&t).await?;
            Ok::<_, FilterError>(out)
        });
        futures::future::try_join_all(futures).await
    }
}

static INSTANCE: OnceCell<Arc<PrivacyFilter>> = OnceCell::new();

/// Global handle. Enclave host + repo come from
/// `SCREENPIPE_PRIVACY_FILTER_ENCLAVE` / `SCREENPIPE_PRIVACY_FILTER_REPO`,
/// defaulting to the screenpipe-published enclave + its source repo so that
/// Tinfoil's measurement comparison ties this client to the exact open
/// source code at github.com/screenpipe/privacy-filter.
pub fn global() -> Arc<PrivacyFilter> {
    INSTANCE
        .get_or_init(|| {
            let enclave = std::env::var("SCREENPIPE_PRIVACY_FILTER_ENCLAVE")
                .unwrap_or_else(|_| DEFAULT_ENCLAVE.to_string());
            let repo = std::env::var("SCREENPIPE_PRIVACY_FILTER_REPO")
                .unwrap_or_else(|_| DEFAULT_REPO.to_string());
            Arc::new(PrivacyFilter::new(enclave, repo))
        })
        .clone()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn short_text_bypasses_round_trip() {
        // Using a bogus URL — the assertion is that the call never happens
        // for under-threshold input, so it doesn't matter that the URL is
        // unreachable.
        // These tests never reach the network — they exercise the cache /
        // short-text bypass. The enclave + repo strings are bogus on purpose:
        // if anything tries to actually attest, the test will fail loud
        // rather than silently calling out.
        let f = PrivacyFilter::new("never.invalid".to_string(), "test/never".to_string());
        let out = f.filter("hi").await.unwrap();
        assert_eq!(out, "hi");
    }

    #[tokio::test]
    async fn cache_returns_same_result_without_network() {
        // Seed the cache by hand and verify we hit it instead of the network.
        // These tests never reach the network — they exercise the cache /
        // short-text bypass. The enclave + repo strings are bogus on purpose:
        // if anything tries to actually attest, the test will fail loud
        // rather than silently calling out.
        let f = PrivacyFilter::new("never.invalid".to_string(), "test/never".to_string());
        let text = "my email is louis.beaumont@gmail.com and this is long enough to filter";
        let mut hasher = Sha256::new();
        hasher.update(text.as_bytes());
        let key: [u8; 32] = hasher.finalize().into();
        f.cache
            .insert(
                key,
                Arc::new("my email is [EMAIL] and this is long enough to filter".into()),
            )
            .await;
        let out = f.filter(text).await.unwrap();
        assert_eq!(out, "my email is [EMAIL] and this is long enough to filter");
    }

    #[tokio::test]
    async fn batch_preserves_order_and_uses_cache() {
        // These tests never reach the network — they exercise the cache /
        // short-text bypass. The enclave + repo strings are bogus on purpose:
        // if anything tries to actually attest, the test will fail loud
        // rather than silently calling out.
        let f = PrivacyFilter::new("never.invalid".to_string(), "test/never".to_string());
        // Seed all three results in the cache so no network call fires.
        for (text, redacted) in [
            ("alpha-text-block-one".to_string(), "alpha-cached"),
            ("beta-text-block-two".to_string(), "beta-cached"),
            ("gamma-text-block-three".to_string(), "gamma-cached"),
        ] {
            let mut hasher = Sha256::new();
            hasher.update(text.as_bytes());
            let key: [u8; 32] = hasher.finalize().into();
            f.cache.insert(key, Arc::new(redacted.into())).await;
        }
        let out = f
            .filter_batch(vec![
                "alpha-text-block-one".into(),
                "beta-text-block-two".into(),
                "gamma-text-block-three".into(),
            ])
            .await
            .unwrap();
        assert_eq!(out, vec!["alpha-cached", "beta-cached", "gamma-cached"]);
    }
}
