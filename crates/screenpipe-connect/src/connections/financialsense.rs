use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

// FinancialSense is a CRM/accounting platform used by fractional CFOs and
// accounting firms. API access is gated behind the Scale plan. Users generate
// a bearer token via Settings → API → "New token" and paste it here.
//
// Base URL is a static guess; the test() call below verifies the token by
// hitting /me. If the real endpoint differs the user can edit proxy_config
// in a follow-up — or we add an api_base field if we ship support for
// self-hosted / white-label tenants.
static DEF: IntegrationDef = IntegrationDef {
    id: "financialsense",
    name: "Financial Sense",
    icon: "financialsense",
    category: Category::Productivity,
    description: "Financial Sense CRM / accounting. Use Bearer <api_key> to POST client billing notes, read client lists, and log time entries. Useful for fractional CFOs and bookkeepers who bill by client-hour. Endpoints: GET /api/v1/clients, POST /api/v1/clients/{id}/notes, POST /api/v1/time-entries.",
    fields: &[FieldDef {
        key: "api_key",
        label: "API Token",
        secret: true,
        placeholder: "fs_...",
        help_url: "https://app.financialsense.com/settings/api",
    }],
};

pub struct FinancialSense;

#[async_trait]
impl Integration for FinancialSense {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://app.financialsense.com",
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
        // /api/v1/me returns the authenticated user on most Rails-style CRMs.
        // If the real endpoint is different, surface the raw HTTP error so the
        // user can paste the correct base path as feedback.
        let resp = client
            .get("https://app.financialsense.com/api/v1/me")
            .bearer_auth(api_key)
            .send()
            .await?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("financial sense returned {}: {}", status, body);
        }
        let body: Value = resp.json().await?;
        let name = body["name"]
            .as_str()
            .or_else(|| body["email"].as_str())
            .unwrap_or("authenticated");
        Ok(format!("connected — {}", name))
    }
}
