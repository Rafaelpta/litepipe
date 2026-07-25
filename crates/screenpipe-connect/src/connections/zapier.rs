use super::{require_str, Category, FieldDef, Integration, IntegrationDef};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{json, Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "zapier",
    name: "Zapier",
    icon: "zapier",
    category: Category::Productivity,
    description:
        "Send data to Zapier Zaps via webhook. POST JSON to the webhook URL with any payload.",
    fields: &[FieldDef {
        key: "webhook_url",
        label: "Webhook URL",
        secret: true,
        placeholder: "https://hooks.zapier.com/hooks/catch/...",
        help_url: "https://zapier.com/help/create/code-webhooks/trigger-zaps-from-webhooks",
    }],
};

pub struct Zapier;

#[async_trait]
impl Integration for Zapier {
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
            .json(&json!({"source": "screenpipe", "event": "test", "message": "screenpipe connected"}))
            .send()
            .await?
            .error_for_status()?;
        Ok("test event sent to Zapier webhook".into())
    }
}
