use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "stripe",
    name: "Stripe",
    icon: "stripe",
    category: Category::Productivity,
    description: "Access Stripe payments, customers, and subscriptions. Use the Stripe API with Authorization: Bearer <secret_key>. Endpoints: GET /v1/charges, GET /v1/customers, GET /v1/subscriptions",
    fields: &[FieldDef {
        key: "api_key",
        label: "Secret Key",
        secret: true,
        placeholder: "sk_live_...",
        help_url: "https://dashboard.stripe.com/apikeys",
    }],
};

pub struct Stripe;

#[async_trait]
impl Integration for Stripe {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://api.stripe.com",
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
        let resp: Value = client
            .get("https://api.stripe.com/v1/balance")
            .bearer_auth(api_key)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let available = resp["available"]
            .as_array()
            .and_then(|a| a.first())
            .and_then(|b| b["amount"].as_i64())
            .unwrap_or(0);
        let currency = resp["available"]
            .as_array()
            .and_then(|a| a.first())
            .and_then(|b| b["currency"].as_str())
            .unwrap_or("usd");
        Ok(format!(
            "connected — balance: {}.{:02} {}",
            available / 100,
            (available % 100).abs(),
            currency
        ))
    }
}
