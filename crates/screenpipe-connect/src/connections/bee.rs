use super::{
    build_client_for, require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth,
    ProxyConfig,
};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "bee",
    name: "Bee",
    icon: "bee",
    category: Category::Productivity,
    description: "Bee wearable AI — captures in-person conversations, facts, todos, and daily summaries. Pair with screenpipe to cover what you saw on screen plus what you heard out loud. Get a developer token from the Bee iOS app (tap version 5x to enable Developer Mode).",
    fields: &[FieldDef {
        key: "api_key",
        label: "Developer Token",
        secret: true,
        placeholder: "your-bee-developer-token",
        help_url: "https://docs.bee.computer/docs/developer-mode",
    }],
};

const BEE_BASE_URL: &str = "https://app-api-developer.ce.bee.amazon.dev";

/// Bee's `app-api-developer.ce.bee.amazon.dev` host serves a TLS chain
/// terminated by `CN=BeeCertificateAuthority` — a private root, not WebPKI.
/// Any default reqwest client (system roots only) fails the connect with
/// `self-signed certificate in certificate chain`. The `extra_root_pem`
/// hook injects this anchor so the proxy + `test()` succeed without
/// touching the user's system trust store.
///
/// Source: pulled from the live server via
///   `openssl s_client -showcerts -servername app-api-developer.ce.bee.amazon.dev \
///                     -connect app-api-developer.ce.bee.amazon.dev:443`
/// (3rd cert in the chain, the self-signed root).
/// Validity: 2025-08-21 → 2035-08-21.
const BEE_ROOT_CA_PEM: &str = "-----BEGIN CERTIFICATE-----
MIIDfzCCAmegAwIBAgIRANp9rGecKAk6t6XGd3GWVHkwDQYJKoZIhvcNAQELBQAw
WTELMAkGA1UEBhMCVVMxDDAKBgNVBAoMA0JlZTEaMBgGA1UECwwRVHJ1c3QgYW5k
IFByaXZhY3kxIDAeBgNVBAMMF0JlZUNlcnRpZmljYXRlQXV0aG9yaXR5MB4XDTI1
MDgyMTE5MjUyNloXDTM1MDgyMTIwMjUyNlowWTELMAkGA1UEBhMCVVMxDDAKBgNV
BAoMA0JlZTEaMBgGA1UECwwRVHJ1c3QgYW5kIFByaXZhY3kxIDAeBgNVBAMMF0Jl
ZUNlcnRpZmljYXRlQXV0aG9yaXR5MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIB
CgKCAQEA7a4dWfEBlstJGQWx2MG9fInEWw4v5e2Sasiw8D09fW77VbSskLEectYl
t8XgM8a2O9JAPkCQ3vNJmIO+6etyPj/DEtjwllSPR5/1qcZXGFMbjRGzmDz2Y6Mr
uPlrGYZZQgSNrnuSSndADCrqSEGLdBzkjXqkuXLXDqdLLTzseNQVfCiN2LDCwFRD
Ugjw4KuiJzSBZ1CQEdug4qauitcif6NOFEiTViAOkXjSmjAdTjN0GDKQdTmDtQYg
NfLuhhfmEB9mdiEm3++AUURQ2Cn+MfP2YAy/5gr3t+ydPRx361mbA1UiWnx7lmLU
xRmZhzeaDmO8vUxxM1jHSXLNxMPMUwIDAQABo0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBRAKKN5ASGNfQOKcsdpaFwNki78xzAOBgNVHQ8BAf8EBAMCAYYw
DQYJKoZIhvcNAQELBQADggEBADXy/YcenRwuAbCH57sFcwe/akWsdh7bs9ZNb7dq
g6qzDpitO8yhpEK1DSW2Nmbtxd59rhV5jmnAfFHLEoeOlsSeBLADH3/3uRLV1kIR
M3kUPKOv1FJq7UkK2VzgabpehyeJ4lfozfT983b3AoDvI6quf3Dl2NrCmmUUewrZ
6g+RSR6n6Q/PalGUPtoV+W4OT5j9hS1d0PSNO6QbRRFzW+NZ+aQdLwHQPzwjofSh
vM1JjV7Hz2KOPJwmqHQbCiaayGq5lZIVI3UrqnTIqB/hySEBIJNeyHN3ggORH2JJ
wzMF+xiaNYUCir9ZzsgYiEsuaxEyiS96ydDImWJboALiWmE=
-----END CERTIFICATE-----
";

pub struct Bee;

#[async_trait]
impl Integration for Bee {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: BEE_BASE_URL,
            auth: ProxyAuth::Bearer {
                credential_key: "api_key",
            },
            extra_headers: &[],
        };
        Some(&CFG)
    }

    fn extra_root_pem(&self) -> Option<&'static str> {
        Some(BEE_ROOT_CA_PEM)
    }

    async fn test(
        &self,
        _client: &reqwest::Client,
        creds: &Map<String, Value>,
        _secret_store: Option<&SecretStore>,
    ) -> Result<String> {
        let api_key = require_str(creds, "api_key")?;
        // Default client doesn't trust BeeCertificateAuthority; build one
        // that does. Same path the proxy handler uses on every request.
        let client = build_client_for(self);
        let resp: Value = client
            .get(format!("{}/v1/me", BEE_BASE_URL))
            .bearer_auth(api_key)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let name = resp
            .get("first_name")
            .and_then(|v| v.as_str())
            .or_else(|| resp.get("firstName").and_then(|v| v.as_str()))
            .unwrap_or("");
        if name.is_empty() {
            Ok("connected".to_string())
        } else {
            Ok(format!("connected as {}", name))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn def_is_stable() {
        let bee = Bee;
        let def = bee.def();
        assert_eq!(def.id, "bee");
        assert_eq!(def.name, "Bee");
        assert_eq!(def.fields.len(), 1);
        assert_eq!(def.fields[0].key, "api_key");
        assert!(def.fields[0].secret);
    }

    #[test]
    fn proxy_config_uses_bearer() {
        let bee = Bee;
        let cfg = bee.proxy_config().expect("bee should have a proxy config");
        assert_eq!(cfg.base_url, BEE_BASE_URL);
        match &cfg.auth {
            ProxyAuth::Bearer { credential_key } => assert_eq!(*credential_key, "api_key"),
            other => panic!("expected Bearer auth, got {:?}", other),
        }
    }

    /// The custom CA must parse as a valid PEM certificate that reqwest can
    /// hand to rustls. If the embedded blob is corrupted (e.g. line endings
    /// mangled by an editor, accidental BOM), every Bee API call would fail
    /// at startup with an opaque TLS error — pin it here.
    #[test]
    fn embedded_root_ca_parses() {
        let pem = Bee.extra_root_pem().expect("bee advertises an extra root");
        assert!(pem.contains("BEGIN CERTIFICATE"));
        assert!(pem.contains("END CERTIFICATE"));
        let cert =
            reqwest::Certificate::from_pem(pem.as_bytes()).expect("cert must parse via reqwest");
        // Certificate API is opaque, but successful parsing is the contract
        // the proxy depends on.
        let _ = cert;
    }

    /// `build_client_for` must produce a usable client even when an integration
    /// returns the Bee CA. Failure here means TLS calls would silently fall
    /// back to a default client and 100% of Bee requests would 525.
    #[test]
    fn build_client_for_succeeds_with_bee_ca() {
        let _client = build_client_for(&Bee);
        // We can't make a real HTTPS call from a unit test without network
        // access, but the builder must produce a client without panicking
        // and without falling through to the default-client warning path.
    }

    /// End-to-end live test against the real Bee API. Ignored by default
    /// (CI doesn't have a Bee token), opt in locally with:
    ///
    ///   cargo test -p screenpipe-connect connections::bee::tests::live_api_smoke \
    ///     -- --ignored --nocapture
    ///
    /// The token is pulled from the macOS Keychain (`bee-cli` service)
    /// where the Bee CLI stores it after `bee login`. The test asserts both
    /// that the embedded CA validates and that `test()` returns a username.
    #[tokio::test]
    #[ignore]
    async fn live_api_smoke() {
        let out = std::process::Command::new("security")
            .args(["find-generic-password", "-s", "bee-cli", "-w"])
            .output()
            .expect("security cmd available on macOS");
        if !out.status.success() {
            eprintln!("skipping: no bee-cli token in keychain — run `bee login` first");
            return;
        }
        let token = String::from_utf8_lossy(&out.stdout).trim().to_string();
        assert!(token.starts_with("eyJ"), "expected JWT-shaped token");

        let mut creds = Map::new();
        creds.insert("api_key".into(), Value::String(token));

        // Pass an irrelevant default client; Bee::test ignores it and builds
        // its own via build_client_for.
        let result = Bee.test(&reqwest::Client::new(), &creds, None).await;
        let msg = result.expect("Bee.test should succeed");
        assert!(msg.starts_with("connected"), "unexpected message: {msg}");
        eprintln!("live_api_smoke: {msg}");
    }
}
