use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "clickup",
    name: "ClickUp",
    icon: "clickup",
    category: Category::Productivity,
    description: "Create and manage tasks in ClickUp. Use the ClickUp API v2 at https://api.clickup.com/api/v2 with Authorization header set to the API key.",
    fields: &[FieldDef {
        key: "api_key",
        label: "API Key",
        secret: true,
        placeholder: "pk_...",
        help_url: "https://clickup.com/api/developer-tools/authentication#personal-token",
    }],
};

pub struct ClickUp;

#[async_trait]
impl Integration for ClickUp {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://api.clickup.com/api/v2",
            auth: ProxyAuth::Header {
                name: "Authorization",
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
            .get("https://api.clickup.com/api/v2/user")
            .header("Authorization", api_key)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let name = resp["user"]["username"].as_str().unwrap_or("unknown");
        Ok(format!("connected as {}", name))
    }
}
