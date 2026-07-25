//! Pocket AI (heypocket.com) — voice recorder hardware with cloud transcription.
//!
//! API docs: https://docs.heypocketai.com/docs/api
//! Auth: API key with `pk_` prefix, sent as `Authorization: Bearer pk_...`.
//! Base URL: https://public.heypocketai.com
//!
//! Useful endpoints (all under /api/v1/public):
//!   GET    /recordings                     — list with date/tag filters + pagination
//!   GET    /recordings/{id}                — single recording detail (transcript, summary)
//!   GET    /recordings/{id}/audio          — signed download URL for audio file
//!   POST   /recordings:search              — full-text search across recordings
//!   GET    /tags                           — list user's tags
//!
//! Users get the API key from Pocket Settings → Developer → API Keys.

use super::{require_str, Category, FieldDef, Integration, IntegrationDef, ProxyAuth, ProxyConfig};
use anyhow::Result;
use async_trait::async_trait;
use screenpipe_secrets::SecretStore;
use serde_json::{Map, Value};

static DEF: IntegrationDef = IntegrationDef {
    id: "pocket",
    name: "Pocket",
    icon: "pocket",
    category: Category::Productivity,
    description: "Access recordings, transcripts, summaries, and tags from your Pocket AI \
        voice recorder. Use the Pocket REST API with Bearer auth. \
        Base URL: https://public.heypocketai.com/api/v1/public. \
        Useful endpoints: \
        GET /recordings — list recordings (query: start_date, end_date, tag_ids, page, limit). \
        GET /recordings/{id} — single recording with transcript and summary. \
        GET /recordings/{id}/audio — signed audio download URL. \
        POST /recordings:search — full-text search (body: {query, limit}). \
        GET /tags — list tags. \
        Pocket also exposes an MCP server at https://public.heypocketai.com/mcp for direct AI agent integration.",
    fields: &[FieldDef {
        key: "api_key",
        label: "API Key",
        secret: true,
        placeholder: "pk_...",
        help_url: "https://docs.heypocketai.com/docs/api/organization/api-keys",
    }],
};

pub struct Pocket;

#[async_trait]
impl Integration for Pocket {
    fn def(&self) -> &'static IntegrationDef {
        &DEF
    }

    fn proxy_config(&self) -> Option<&'static ProxyConfig> {
        static CFG: ProxyConfig = ProxyConfig {
            base_url: "https://public.heypocketai.com/api/v1/public",
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
        // List 1 recording — cheapest call that confirms auth + connectivity.
        // Returns {"success":true, "data":[...], "pagination":{...}} on valid key,
        // {"success":false, "error":"API key not found"} HTTP 401 on bad key.
        let resp: Value = client
            .get("https://public.heypocketai.com/api/v1/public/recordings?limit=1")
            .bearer_auth(api_key)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let total = resp["pagination"]["total"].as_u64().unwrap_or(0);
        Ok(format!("connected, {} recording(s) total", total))
    }
}
