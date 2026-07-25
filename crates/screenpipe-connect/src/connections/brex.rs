use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "brex",
    name: "Brex",
    icon: "brex",
    category: Category::Productivity,
    description: "Access Brex transactions, accounts, and cards. Use the Brex API with Authorization: Bearer <token>. Endpoints: GET /v2/transactions/card/primary, GET /v2/accounts",
    fields: &[FieldDef {
        key: "api_token",
        label: "API Token",
        secret: true,
        placeholder: "brex_...",
        help_url: "https://developer.brex.com/docs/authentication/",
    }],
};

pub struct Brex;

#[async_trait]
impl Integration for Brex {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://platform.brexapis.com",
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
            .get("https://platform.brexapis.com/v2/accounts")
            .bearer_auth(api_token)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let count = resp["items"].as_array().map(|a| a.len()).unwrap_or(0);
        Ok(format!("connected — {} account(s) found", count))
    }
}
