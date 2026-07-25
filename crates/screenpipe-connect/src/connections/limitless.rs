use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "limitless",
    name: "Limitless",
    icon: "limitless",
    category: Category::Productivity,
    description: "Access your Limitless pendant lifelogs, transcripts, and audio. Use the Limitless API with X-API-Key header. Base URL: https://api.limitless.ai/v1",
    fields: &[FieldDef {
        key: "api_key",
        label: "API Key",
        secret: true,
        placeholder: "your-limitless-api-key",
        help_url: "https://www.limitless.ai/developers",
    }],
};

pub struct Limitless;

#[async_trait]
impl Integration for Limitless {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://api.limitless.ai/v1",
            auth: ProxyAuth::Header {
                name: "X-API-Key",
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
            .get("https://api.limitless.ai/v1/lifelogs?limit=1")
            .header("X-API-Key", api_key)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let count = resp["lifelogs"].as_array().map(|a| a.len()).unwrap_or(0);
        Ok(format!("connected, fetched {} lifelog(s)", count))
    }
}
