use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

// Bitrix24 inbound webhooks embed auth in the path:
//   https://<portal>.bitrix24.<tld>/rest/<user_id>/<webhook_secret>/<api.method>.json
// Splitting the URL into three fields lets us keep `https://` in the static
// template (passes the HTTPS validation in the proxy resolver) while still
// adapting per-tenant. Different regions use different TLDs (.com, .eu, .ru,
// .de, etc.), so `domain` is the full hostname not just a subdomain.
static DEF: IntegrationDef = IntegrationDef {
    id: "bitrix24",
    name: "Bitrix24",
    icon: "bitrix24",
    category: Category::Productivity,
    description: "Manage Bitrix24 CRM contacts, deals, and tasks. \
        Inbound webhook auth — append API method to the proxy base URL, \
        e.g. POST /crm.deal.add.json with JSON body. \
        See https://apidocs.bitrix24.com/api-reference/ for endpoints.",
    fields: &[
        FieldDef {
            key: "domain",
            label: "Portal Domain",
            secret: false,
            placeholder: "yourcompany.bitrix24.com",
            help_url: "https://apidocs.bitrix24.com/api-reference/common/system/index.html",
        },
        FieldDef {
            key: "user_id",
            label: "User ID",
            secret: false,
            placeholder: "1",
            help_url: "https://apidocs.bitrix24.com/local-integrations/local-webhooks.html",
        },
        FieldDef {
            key: "webhook_secret",
            label: "Webhook Secret",
            secret: true,
            placeholder: "abcd1234efgh5678ijkl9012mnop3456",
            help_url: "https://apidocs.bitrix24.com/local-integrations/local-webhooks.html",
        },
    ],
};

pub struct Bitrix24;

#[async_trait]
impl Integration for Bitrix24 {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        // Auth is in the URL path itself (the webhook secret), not headers.
        // ProxyAuth::None means the resolver doesn't inject Authorization.
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://{domain}/rest/{user_id}/{webhook_secret}",
            auth: ProxyAuth::None,
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
        let domain = require_str(creds, "domain")?;
        let user_id = require_str(creds, "user_id")?;
        let secret = require_str(creds, "webhook_secret")?;
        // app.info is the canonical "is the webhook valid" endpoint — returns
        // the application metadata if the secret is correct, 401 otherwise.
        let url = format!(
            "https://{}/rest/{}/{}/app.info.json",
            domain, user_id, secret
        );
        client.get(&url).send().await?.error_for_status()?;
        Ok("connected to Bitrix24".into())
    }
}
