pub mod connections;
pub mod ics_calendar;
pub mod mcp_servers;
pub mod mdns;
pub mod oauth;
pub mod oauth_refresh_scheduler;
pub mod remote_sync;
pub mod sync_scheduler;
pub mod unstructured_ocr;
pub mod whatsapp;

#[cfg(target_os = "macos")]
pub mod calendar;

#[cfg(target_os = "windows")]
pub mod calendar_windows;
