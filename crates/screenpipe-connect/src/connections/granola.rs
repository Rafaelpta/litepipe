use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "granola",
    name: "Granola",
    icon: "granola",
    category: Category::Productivity,
    description: "Access your Granola meeting notes and transcripts. Use GET https://public-api.granola.ai/v1/notes with Authorization: Bearer <api_key>. Add ?include=transcript to include transcripts.",
    fields: &[FieldDef {
        key: "api_key",
        label: "API Key",
        secret: true,
        placeholder: "grn_...",
        help_url: "https://docs.granola.ai/help-center/sharing/integrations/personal-api",
    }],
};

pub struct Granola;

#[async_trait]
impl Integration for Granola {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://public-api.granola.ai/v1",
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
        let resp: Value = client
            .get("https://public-api.granola.ai/v1/notes")
            .bearer_auth(api_key)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let count = resp["notes"].as_array().map(|a| a.len()).unwrap_or(0);
        Ok(format!("connected, found {} note(s)", count))
    }
}
