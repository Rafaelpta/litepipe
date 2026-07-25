use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{json, Map, Value};

// Fireflies.ai meeting transcription. Public GraphQL API at
// https://api.fireflies.ai/graphql with Authorization: Bearer <key>. Users
// generate the key at https://app.fireflies.ai/integrations/custom/fireflies.
static DEF: IntegrationDef = IntegrationDef {
    id: "fireflies",
    name: "Fireflies.ai",
    icon: "fireflies",
    category: Category::Productivity,
    description: "Fireflies.ai meeting notes. GraphQL API at https://api.fireflies.ai/graphql, Authorization: Bearer <api_key>. Useful queries: { transcripts(limit:10){id,title,date,summary,sentences{text,speaker_name}} }, { user{email,name} }. Use to pull recent meeting transcripts, action items, and sentences for a pipe to summarize or cross-reference screen activity.",
    fields: &[FieldDef {
        key: "api_key",
        label: "API Key",
        secret: true,
        placeholder: "fireflies api key",
        help_url: "https://app.fireflies.ai/integrations/custom/fireflies",
    }],
};

pub struct Fireflies;

#[async_trait]
impl Integration for Fireflies {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://api.fireflies.ai",
            auth: ProxyAuth::Bearer {
                credential_key: "api_key",
            },
            extra_headers: &[("Content-Type", "application/json")],
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
        let resp = client
            .post("https://api.fireflies.ai/graphql")
            .bearer_auth(api_key)
            .json(&json!({ "query": "{ user { email name } }" }))
            .send()
            .await?;
        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("fireflies returned {}: {}", status, body);
        }
        let body: Value = resp.json().await?;
        if let Some(errs) = body.get("errors").and_then(|e| e.as_array()) {
            if let Some(msg) = errs.first().and_then(|e| e["message"].as_str()) {
                anyhow::bail!("fireflies graphql error: {}", msg);
            }
        }
        let email = body["data"]["user"]["email"].as_str().unwrap_or("");
        let name = body["data"]["user"]["name"]
            .as_str()
            .unwrap_or("authenticated");
        Ok(if email.is_empty() {
            format!("connected — {}", name)
        } else {
            format!("connected — {} ({})", name, email)
        })
    }
}
