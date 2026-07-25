use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "airtable",
    name: "Airtable",
    icon: "airtable",
    category: Category::Productivity,
    description: "Read and write Airtable bases. Use the Airtable API with Authorization: Bearer <token>. Base ID starts with 'app'.",
    fields: &[
        FieldDef {
            key: "api_token",
            label: "API Token",
            secret: true,
            placeholder: "pat...",
            help_url: "https://airtable.com/create/tokens",
        },
        FieldDef {
            key: "base_id",
            label: "Base ID",
            secret: false,
            placeholder: "appXXXXXXXXXX",
            help_url: "https://airtable.com/create/tokens",
        },
    ],
};

pub struct Airtable;

#[async_trait]
impl Integration for Airtable {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://api.airtable.com",
            auth: ProxyAuth::Bearer {
                credential_key: "api_token",
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
        let api_token = require_str(creds, "api_token")?;
        let resp: Value = client
            .get("https://api.airtable.com/v0/meta/bases")
            .bearer_auth(api_token)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let count = resp["bases"].as_array().map(|a| a.len()).unwrap_or(0);
        Ok(format!("connected, {} bases found", count))
    }
}
