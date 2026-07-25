//! CLI: replay one or more TOML scenarios through the meeting-detection
//! state machine and emit JSON metrics on stdout (one JSON object per
//! scenario, newline-delimited). Exits non-zero if any non-xfail
//! scenario fails its expectations.

use anyhow::Result;
use clap::Parser;
use std::path::PathBuf;

use screenpipe_meeting_eval::{load_scenario, run_scenario};

#[derive(Parser, Debug)]
#[command(about = "Replay meeting-detection scenarios and emit JSON metrics")]
struct Args {
    /// Scenario TOML files to run (one JSON object per scenario on stdout).
    #[arg(required = true)]
    scenarios: Vec<PathBuf>,
    /// Don't exit non-zero even if expectations fail. Useful for
    /// gathering baseline numbers before tightening expectations.
    #[arg(long)]
    no_gate: bool,
}

fn main() -> Result<()> {
    let args = Args::parse();
    let mut any_real_failure = false;

    for path in &args.scenarios {
        let scenario = load_scenario(path)?;
        let metrics = run_scenario(&scenario);
        let line = serde_json::to_string(&metrics)?;
        println!("{}", line);

        if !metrics.assertion_failures.is_empty() {
            let is_xfail = metrics.xfail.is_some();
            if is_xfail {
                eprintln!(
                    "xfail (expected): {} — {} failure(s): {:?}",
                    metrics.scenario,
                    metrics.assertion_failures.len(),
                    metrics.assertion_failures
                );
            } else {
                eprintln!(
                    "FAIL: {} — {} failure(s): {:?}",
                    metrics.scenario,
                    metrics.assertion_failures.len(),
                    metrics.assertion_failures
                );
                any_real_failure = true;
            }
        }
    }

    if any_real_failure && !args.no_gate {
        std::process::exit(1);
    }
    Ok(())
}
