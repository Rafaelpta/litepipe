use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "toggl",
    name: "Toggl",
    icon: "toggl",
    category: Category::Productivity,
    description: "Track time with Toggl. Use the Toggl API with Basic auth (api_token:api_token). Base URL: https://api.track.toggl.com/api/v9/",
    fields: &[FieldDef {
        key: "api_token",
        label: "API Token",
        secret: true,
        placeholder: "your-api-token",
        help_url: "https://track.toggl.com/profile",
    }],
};

pub struct Toggl;

#[async_trait]
impl Integration for Toggl {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://api.track.toggl.com/api/v9",
            auth: ProxyAuth::BasicAuth {
                username_key: "api_token",
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
        let token = require_str(creds, "api_token")?;
        let resp: Value = client
            .get("https://api.track.toggl.com/api/v9/me")
            .basic_auth(token, Some("api_token"))
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let fullname = resp["fullname"].as_str().unwrap_or("unknown");
        Ok(format!("connected as {}", fullname))
    }
}
