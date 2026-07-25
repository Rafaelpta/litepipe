use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "confluence",
    name: "Confluence",
    icon: "confluence",
    category: Category::Productivity,
    description: "Search and create pages in Confluence. Use the Confluence REST API at https://{domain}/wiki/api/v2 with Basic auth (email + API token).",
    fields: &[
        FieldDef {
            key: "domain",
            label: "Atlassian Domain",
            secret: false,
            placeholder: "yourcompany.atlassian.net",
            help_url: "https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/",
        },
        FieldDef {
            key: "email",
            label: "Email",
            secret: false,
            placeholder: "you@yourcompany.com",
            help_url: "https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/",
        },
        FieldDef {
            key: "api_token",
            label: "API Token",
            secret: true,
            placeholder: "your Atlassian API token",
            help_url: "https://id.atlassian.com/manage-profile/security/api-tokens",
        },
    ],
};

pub struct Confluence;

#[async_trait]
impl Integration for Confluence {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://{domain}/wiki/api/v2",
            auth: ProxyAuth::BasicAuth {
                username_key: "email",
                password_key: "api_token",
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
        let domain = require_str(creds, "domain")?.trim_end_matches('/');
        let email = require_str(creds, "email")?;
        let api_token = require_str(creds, "api_token")?;
        let resp: Value = client
            .get(format!("https://{}/wiki/api/v2/spaces?limit=5", domain))
            .basic_auth(email, Some(api_token))
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let count = resp["results"].as_array().map(|a| a.len()).unwrap_or(0);
        Ok(format!("connected — {} spaces found", count))
    }
}
