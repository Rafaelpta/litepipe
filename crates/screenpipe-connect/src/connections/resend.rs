use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "resend",
    name: "Resend",
    icon: "resend",
    category: Category::Productivity,
    description: "Send transactional emails and manage audiences via Resend. \
        Use the Resend API with Authorization: Bearer <token>. \
        Endpoints: POST /emails (send), POST /emails/batch, GET /domains, \
        POST /audiences, POST /contacts, GET /api-keys. \
        See https://resend.com/docs/api-reference for the full reference.",
    fields: &[FieldDef {
        key: "api_key",
        label: "API Key",
        secret: true,
        placeholder: "re_xxxxxxxxxxxxxxxxxxxxx",
        help_url: "https://resend.com/docs/dashboard/api-keys/introduction",
    }],
};

pub struct Resend;

#[async_trait]
impl Integration for Resend {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://api.resend.com",
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
        // GET /domains is the lightest authenticated endpoint — works on any
        // key tier (full-access or sending-only) and returns 200 + { data: [...] }.
        let resp: Value = client
            .get("https://api.resend.com/domains")
            .bearer_auth(api_key)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let count = resp["data"].as_array().map(|a| a.len()).unwrap_or(0);
        Ok(format!("connected to Resend ({} domain(s))", count))
    }
}
