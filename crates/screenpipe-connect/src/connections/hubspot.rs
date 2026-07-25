use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "hubspot",
    name: "HubSpot",
    icon: "hubspot",
    category: Category::Productivity,
    description: "Manage HubSpot contacts, deals, and activities. Use the HubSpot API with Authorization: Bearer <token>.",
    fields: &[FieldDef {
        key: "api_token",
        label: "API Token",
        secret: true,
        placeholder: "pat-na1-...",
        help_url: "https://knowledge.hubspot.com/integrations/how-do-i-get-my-hubspot-api-key",
    }],
};

pub struct HubSpot;

#[async_trait]
impl Integration for HubSpot {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://api.hubapi.com",
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
        client
            .get("https://api.hubapi.com/crm/v3/objects/contacts?limit=1")
            .bearer_auth(api_token)
            .send()
            .await?
            .error_for_status()?;
        Ok("connected to HubSpot".into())
    }
}
