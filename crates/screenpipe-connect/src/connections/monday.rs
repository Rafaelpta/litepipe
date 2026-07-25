use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "monday",
    name: "Monday.com",
    icon: "monday",
    category: Category::Productivity,
    description: "Manage Monday.com boards, items, and updates. GraphQL API at POST https://api.monday.com/v2 with Authorization: {api_token}. Example query: {\"query\": \"{ boards(limit:5) { id name } }\"}",
    fields: &[FieldDef {
        key: "api_token",
        label: "API Token",
        secret: true,
        placeholder: "your Monday.com API token",
        help_url: "https://support.monday.com/hc/en-us/articles/360005144659-API-Tokens",
    }],
};

pub struct Monday;

#[async_trait]
impl Integration for Monday {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://api.monday.com/v2",
            auth: ProxyAuth::Header {
                name: "Authorization",
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
        let token = require_str(creds, "api_token")?;
        let resp: Value = client
            .post("https://api.monday.com/v2")
            .header("Authorization", token)
            .json(&serde_json::json!({"query": "{ boards(limit:5) { id name } }"}))
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let count = resp
            .pointer("/data/boards")
            .and_then(|b| b.as_array())
            .map(|a| a.len())
            .unwrap_or(0);
        Ok(format!("authenticated — {} board(s) found", count))
    }
}
