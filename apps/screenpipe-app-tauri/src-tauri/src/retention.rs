//! Local data retention. Talks only to the local capture engine.
//!
//! litepipe note: the upstream project kept this next to its cloud sync module.
//! litepipe has no cloud sync, so retention lives on its own here.

use crate::recording::{local_api_context_from_app, LocalApiContext};
use crate::store::SettingsStore;
use tauri::AppHandle;
use tracing::{info, warn};

fn apply_local_api_auth(
    api: &LocalApiContext,
    request: reqwest::RequestBuilder,
) -> reqwest::RequestBuilder {
    api.apply_auth(request)
}

/// Auto-start local data retention on app launch.
pub async fn auto_start_retention(app: &AppHandle) {
    let settings = match SettingsStore::get(app) {
        Ok(Some(s)) => s,
        _ => return,
    };

    // litepipe default: on. Disk stays lean out of the box. This is safe because
    // the default mode is `media`, which only reclaims old mp4/wav/jpeg files
    // and KEEPS all DB rows (search, timeline, transcripts) — nothing that was
    // captured as text is lost. The retention-settings UI mirrors this default
    // (`localRetentionEnabled ?? true`) so the toggle visibly shows "on" and a
    // user can turn it off from Settings → Storage.
    let enabled = settings
        .extra
        .get("localRetentionEnabled")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    if !enabled {
        return;
    }

    let days = settings
        .extra
        .get("localRetentionDays")
        .and_then(|v| v.as_u64())
        .unwrap_or(30) as u32;

    let mode = settings
        .extra
        .get("localRetentionMode")
        .and_then(|v| v.as_str())
        .filter(|s| *s == "media" || *s == "all")
        .unwrap_or("media");

    let client = reqwest::Client::new();
    let api = local_api_context_from_app(app);
    let configure_req = serde_json::json!({
        "enabled": true,
        "retention_days": days,
        "mode": mode,
    });

    match apply_local_api_auth(&api, client.post(api.url("/retention/configure")))
        .json(&configure_req)
        .send()
        .await
    {
        Ok(response) if response.status().is_success() => {
            info!(
                "local retention auto-started (retention={}d, mode={})",
                days, mode
            );
        }
        Ok(response) => {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            warn!("local retention auto-start failed ({}): {}", status, body);
        }
        Err(e) => {
            warn!("local retention auto-start: server not reachable: {}", e);
        }
    }
}
