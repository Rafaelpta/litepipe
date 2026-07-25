use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "pipedrive",
    name: "Pipedrive",
    icon: "pipedrive",
    category: Category::Productivity,
    description: "Access Pipedrive deals, contacts, and activities. Use the Pipedrive API with api_token query param. Endpoints: GET /v1/deals, GET /v1/persons, GET /v1/activities",
    fields: &[
        FieldDef {
            key: "api_token",
            label: "API Token",
            secret: true,
            placeholder: "your pipedrive api token",
            help_url: "https://pipedrive.readme.io/docs/how-to-find-the-api-token",
        },
        FieldDef {
            key: "domain",
            label: "Company Domain",
            secret: false,
            placeholder: "yourcompany",
            help_url: "https://pipedrive.readme.io/docs/core-api-concepts-about-pipedrive-api",
        },
    ],
};

pub struct Pipedrive;

#[async_trait]
impl Integration for Pipedrive {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://{domain}.pipedrive.com/api/v1",
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
        let domain = require_str(creds, "domain")?;
        let resp: Value = client
            .get(format!(
                "https://{}.pipedrive.com/api/v1/users/me?api_token={}",
                domain, api_token
            ))
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let name = resp["data"]["name"].as_str().unwrap_or("unknown");
        Ok(format!("connected as {}", name))
    }
}
