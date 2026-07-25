use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

// Otter.ai meeting transcription. Public API surface is minimal compared to
// Fireflies — Otter exposes https://otter.ai/forward/api/v1 behind an API key.
// The token field name and base URL below are best-effort; users with a
// different setup (e.g. Otter Business with SSO) can report back and we adjust.
static DEF: IntegrationDef = IntegrationDef {
    id: "otter",
    name: "Otter.ai",
    icon: "otter",
    category: Category::Productivity,
    description: "Otter.ai meeting transcription. Pass the API key via Authorization: Bearer <api_key> to https://otter.ai/forward/api/v1. Typical endpoints: /speeches (list recent meetings), /speech/{id} (transcript + speakers). Use to cross-reference meeting transcripts with screen activity.",
    fields: &[FieldDef {
        key: "api_key",
        label: "API Key",
        secret: true,
        placeholder: "otter api key",
        help_url: "https://otter.ai/account/api",
    }],
};

pub struct Otter;

#[async_trait]
impl Integration for Otter {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://otter.ai",
            auth: ProxyAuth::Bearer {
                credential_key: "api_key",
            },
            extra_headers: &[],
        };
        Some(&CFG)
    }

    async fn test(
        &self,
        client: &reqwest::Client,
        creds: &Map<String, Value>,
        _secret_store: Option<&SecretStore>,
    ) -> Result<String> {
        let api_key = require_str(creds, "api_key")?;
        let resp = client
            .get("https://otter.ai/forward/api/v1/user")
            .bearer_auth(api_key)
            .send()
            .await?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("otter returned {}: {}", status, body);
        }
        let body: Value = resp.json().await.unwrap_or(Value::Null);
        let name = body["name"]
            .as_str()
            .or_else(|| body["email"].as_str())
            .unwrap_or("authenticated");
        Ok(format!("connected — {}", name))
    }
}
