use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "sentry",
    name: "Sentry",
    icon: "sentry",
    category: Category::Productivity,
    description: "Access Sentry issues and events. Use the Sentry API with Authorization: Bearer <auth_token>. Endpoints: GET /api/0/projects/{org}/{project}/issues/, GET /api/0/organizations/{org}/issues/",
    fields: &[
        FieldDef {
            key: "auth_token",
            label: "Auth Token",
            secret: true,
            placeholder: "sntrys_...",
            help_url: "https://docs.sentry.io/api/guides/create-auth-token/",
        },
        FieldDef {
            key: "organization",
            label: "Organization Slug",
            secret: false,
            placeholder: "my-org",
            help_url: "https://docs.sentry.io/product/accounts/membership/",
        },
    ],
};

pub struct Sentry;

#[async_trait]
impl Integration for Sentry {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://sentry.io/api/0",
            auth: ProxyAuth::Bearer {
                credential_key: "auth_token",
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
        let auth_token = require_str(creds, "auth_token")?;
        let org = require_str(creds, "organization")?;
        let resp: Value = client
            .get(format!(
                "https://sentry.io/api/0/organizations/{}/projects/",
                org
            ))
            .bearer_auth(auth_token)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let count = resp.as_array().map(|a| a.len()).unwrap_or(0);
        Ok(format!("connected — {} project(s) in {}", count, org))
    }
}
