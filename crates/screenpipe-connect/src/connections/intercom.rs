use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "intercom",
    name: "Intercom",
    icon: "intercom",
    category: Category::Productivity,
    description: "Access Intercom conversations, contacts, and companies. Use the Intercom API with Authorization: Bearer <token>. Endpoints: GET /conversations, GET /contacts, GET /companies",
    fields: &[FieldDef {
        key: "api_token",
        label: "Access Token",
        secret: true,
        placeholder: "dG9rOi...",
        help_url: "https://developers.intercom.com/docs/build-an-integration/learn-more/authentication/",
    }],
};

pub struct Intercom;

#[async_trait]
impl Integration for Intercom {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://api.intercom.io",
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
            .get("https://api.intercom.io/me")
            .bearer_auth(api_token)
            .header("Accept", "application/json")
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let name = resp["name"].as_str().unwrap_or("unknown");
        let app_name = resp["app"]["name"].as_str().unwrap_or("");
        Ok(format!("connected as {} ({})", name, app_name))
    }
}
