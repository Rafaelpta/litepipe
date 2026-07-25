use super::AuthCommand;
use anyhow::Result;

pub async fn handle_auth_command(command: &AuthCommand) -> Result<()> {
    match command {
        AuthCommand::Token => print_token().await,
    }
}

async fn print_token() -> Result<()> {
    // All sources (env vars, encrypted SecretStore in db.sqlite, legacy
    // ~/.screenpipe/auth.json) live behind one resolver in `auth_key.rs`.
    // Don't reimplement the priority chain here — divergent copies are
    // exactly what caused agent-driven `connection list` to silently 403.
    if let Some(key) = crate::auth_key::find_api_auth_key().await {
        println!("{}", key);
        return Ok(());
    }

    eprintln!("no API token found. start screenpipe first, or set SCREENPIPE_API_KEY env var.");
    std::process::exit(1);
}
