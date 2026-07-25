use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "salesforce",
    name: "Salesforce",
    icon: "salesforce",
    category: Category::Productivity,
    description: "Query and manage Salesforce CRM records. Use the Salesforce REST API at {instance_url}/services/data/v61.0 with Authorization: Bearer {access_token}.",
    fields: &[
        FieldDef {
            key: "instance_url",
            label: "Instance URL",
            secret: false,
            placeholder: "https://yourorg.my.salesforce.com",
            help_url: "https://help.salesforce.com/s/articleView?id=sf.user_security_token.htm",
        },
        FieldDef {
            key: "access_token",
            label: "Access Token",
            secret: true,
            placeholder: "your Salesforce access token",
            help_url: "https://help.salesforce.com/s/articleView?id=sf.user_security_token.htm",
        },
    ],
};

pub struct Salesforce;

#[async_trait]
impl Integration for Salesforce {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "{instance_url}/services/data/v61.0",
            auth: ProxyAuth::Bearer {
                credential_key: "access_token",
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
        let instance_url = require_str(creds, "instance_url")?.trim_end_matches('/');
        let token = require_str(creds, "access_token")?;
        let resp: Value = client
            .get(format!("{}/services/data/v61.0/sobjects", instance_url))
            .bearer_auth(token)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let count = resp["sobjects"].as_array().map(|a| a.len()).unwrap_or(0);
        Ok(format!("connected — {} objects available", count))
    }
}
