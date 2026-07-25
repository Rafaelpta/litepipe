use super::{require_str, Category, FieldDef, Integration, IntegrationDef};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{json, Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "n8n",
    name: "n8n",
    icon: "n8n",
    category: Category::Productivity,
    description:
        "Send data to n8n workflows via webhook. POST JSON to the webhook URL with any payload.",
    fields: &[FieldDef {
        key: "webhook_url",
        label: "Webhook URL",
        secret: true,
        placeholder: "https://your-n8n.example.com/webhook/...",
        help_url: "https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/",
    }],
};

pub struct N8n;

#[async_trait]
impl Integration for N8n {
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
        Ok("test event sent to n8n webhook".into())
    }
}
