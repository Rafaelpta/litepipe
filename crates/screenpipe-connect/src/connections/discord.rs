use super::{require_str, Category, FieldDef, Integration, IntegrationDef};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{json, Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "discord",
    name: "Discord",
    icon: "discord",
    category: Category::Notification,
    description: "Send messages to Discord. POST to the webhook URL with {\"content\": \"...\"}",
    fields: &[FieldDef {
        key: "webhook_url",
        label: "Webhook URL",
        secret: true,
        placeholder: "https://discord.com/api/webhooks/...",
        help_url: "https://support.discord.com/hc/en-us/articles/228383668",
    }],
};

pub struct Discord;

#[async_trait]
impl Integration for Discord {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    async fn test(
        &self,
        client: &reqwest::Client,
        creds: &Map<String, Value>,
        _secret_store: Option<&SecretStore>,
    ) -> Result<String> {
        let url = require_str(creds, "webhook_url")?;
        client
            .post(url)
            .json(&json!({"content": "screenpipe connected"}))
            .send()
            .await?
            .error_for_status()?;
        Ok("test message sent".into())
    }
}
