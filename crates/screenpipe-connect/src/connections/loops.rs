use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::{anyhow, Result};
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "loops",
    name: "Loops",
    icon: "loops",
    category: Category::Productivity,
    description: "Send transactional and marketing emails via Loops. \
        Use the Loops API with Authorization: Bearer <token>. \
        Endpoints: POST /transactional (send), POST /contacts/create, \
        POST /contacts/update, POST /events (trigger), DELETE /contacts. \
        See https://loops.so/docs/api-reference for the full reference.",
    fields: &[FieldDef {
        key: "api_key",
        label: "API Key",
        secret: true,
        placeholder: "your-loops-api-key",
        help_url: "https://loops.so/docs/api-reference/intro#authentication",
    }],
};

pub struct Loops;

#[async_trait]
impl Integration for Loops {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://app.loops.so/api/v1",
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
        // GET /api-key returns { success: true, teamName: "..." } on a valid key,
        // 401 otherwise — the canonical "is this key live" probe per Loops docs.
        let resp: Value = client
            .get("https://app.loops.so/api/v1/api-key")
            .bearer_auth(api_key)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        if resp["success"].as_bool() != Some(true) {
            return Err(anyhow!("loops api rejected key: {}", resp));
        }
        let team = resp["teamName"].as_str().unwrap_or("unknown team");
        Ok(format!("connected to Loops ({})", team))
    }
}
