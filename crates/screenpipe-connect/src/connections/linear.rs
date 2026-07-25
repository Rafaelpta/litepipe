use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{json, Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "linear",
    name: "Linear",
    icon: "linear",
    category: Category::Productivity,
    description: "Create and manage issues in Linear. Use GraphQL API at https://api.linear.app/graphql with Bearer token.",
    fields: &[FieldDef {
        key: "api_key",
        label: "API Key",
        secret: true,
        placeholder: "lin_api_...",
        help_url: "https://linear.app/settings/api",
    }],
};

pub struct Linear;

#[async_trait]
impl Integration for Linear {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://api.linear.app",
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
        let api_key = require_str(creds, "api_key")?.trim();
        let resp = client
            .post("https://api.linear.app/graphql")
            .header("Authorization", api_key)
            .json(&json!({"query": "{ viewer { id name email } }"}))
            .send()
            .await?;
        let status = resp.status();
        let body: Value = resp.json().await?;
        if !status.is_success() {
            let msg = body["error"]
                .as_str()
                .or_else(|| body["errors"][0]["message"].as_str())
                .unwrap_or("unknown error");
            anyhow::bail!("Linear API error ({}): {}", status, msg);
        }
        if let Some(errors) = body.get("errors") {
            let msg = errors[0]["message"].as_str().unwrap_or("GraphQL error");
            anyhow::bail!("Linear GraphQL error: {}", msg);
        }
        let name = body["data"]["viewer"]["name"].as_str().unwrap_or("unknown");
        Ok(format!("connected as {}", name))
    }
}
