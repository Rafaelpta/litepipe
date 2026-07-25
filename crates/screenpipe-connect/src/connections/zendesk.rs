use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "zendesk",
    name: "Zendesk",
    icon: "zendesk",
    category: Category::Notification,
    description: "Manage support tickets in Zendesk. Use the Zendesk API at https://{subdomain}.zendesk.com/api/v2 with Authorization: Bearer {api_token}.",
    fields: &[
        FieldDef {
            key: "subdomain",
            label: "Subdomain",
            secret: false,
            placeholder: "yourcompany",
            help_url: "https://developer.zendesk.com/api-reference/introduction/security-and-auth/",
        },
        FieldDef {
            key: "email",
            label: "Email",
            secret: false,
            placeholder: "agent@yourcompany.com",
            help_url: "https://developer.zendesk.com/api-reference/introduction/security-and-auth/",
        },
        FieldDef {
            key: "api_token",
            label: "API Token",
            secret: true,
            placeholder: "your Zendesk API token",
            help_url: "https://support.zendesk.com/hc/en-us/articles/4408889192858-Managing-access-to-the-Zendesk-API",
        },
    ],
};

pub struct Zendesk;

#[async_trait]
impl Integration for Zendesk {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://{subdomain}.zendesk.com/api/v2",
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
        let subdomain = require_str(creds, "subdomain")?;
        let email = require_str(creds, "email")?;
        let api_token = require_str(creds, "api_token")?;
        let resp: Value = client
            .get(format!(
                "https://{}.zendesk.com/api/v2/users/me.json",
                subdomain
            ))
            .basic_auth(format!("{}/token", email), Some(api_token))
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let name = resp["user"]["name"].as_str().unwrap_or("unknown");
        Ok(format!("connected as {}", name))
    }
}
