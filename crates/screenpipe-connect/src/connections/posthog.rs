use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "posthog",
    name: "PostHog",
    icon: "posthog",
    category: Category::Productivity,
    description: "Query PostHog analytics — events, insights, cohorts, feature flags. Use the PostHog API with Authorization: Bearer <api_key>. Project-scoped endpoints: GET /api/projects/{project_id}/events/, POST /api/projects/{project_id}/query/. Org endpoints: GET /api/users/@me/.",
    fields: &[
        FieldDef {
            key: "api_key",
            label: "Personal API Key",
            secret: true,
            placeholder: "phx_...",
            help_url: "https://posthog.com/docs/api#how-to-obtain-a-personal-api-key",
        },
        FieldDef {
            key: "project_id",
            label: "Project ID",
            secret: false,
            placeholder: "12345",
            help_url: "https://posthog.com/docs/api#how-to-find-your-project-id",
        },
        FieldDef {
            key: "host",
            label: "Host (leave blank for US Cloud)",
            secret: false,
            placeholder: "us.posthog.com",
            help_url: "https://posthog.com/docs/api#regions",
        },
    ],
};

const DEFAULT_HOST: &str = "us.posthog.com";

fn host_or_default(creds: &Map<String, Value>) -> &str {
    creds
        .get("host")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or(DEFAULT_HOST)
}

pub struct PostHog;

#[async_trait]
impl Integration for PostHog {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        // {host|default} — blank field falls back to us.posthog.com so most
        // users never have to think about regions; EU / self-hosted override.
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://{host|us.posthog.com}",
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
        let project_id = require_str(creds, "project_id")?;
        let host = host_or_default(creds);
        let resp: Value = client
            .get(format!("https://{}/api/projects/{}/", host, project_id))
            .bearer_auth(api_key)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let name = resp["name"].as_str().unwrap_or("unknown");
        Ok(format!("connected to PostHog project: {} ({})", name, host))
    }
}
