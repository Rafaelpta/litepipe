//! Replay a JSONL scan trace through the meeting-detection state
//! machine and emit JSON metrics.
//!
//! Each line of the input file is one `TraceEvent`:
//!
//! ```jsonl
//! {"t":0.0,"in_call":false}
//! {"t":5.0,"in_call":true,"has_audio":true}
//! ```
//!
//! Blank lines and lines starting with `#` are skipped. Combined with
//! a log-scraper (see `evals/traces/extract_from_log.sh`), this lets
//! us turn real meeting_detector log files into regression scenarios.

use std::path::PathBuf;

use anyhow::Result;
use clap::Parser;

use screenpipe_meeting_eval::{load_trace, run_scenario, scenario_from_events};

#[derive(Parser, Debug)]
#[command(about = "Replay a JSONL scan trace through the meeting-detection state machine")]
struct Args {
    /// JSONL trace file (one TraceEvent per line).
    trace: PathBuf,
    /// App name to use in the synthesized ScanResult. Determines
    /// browser vs. native grace (Arc/Chrome/… = browser).
    #[arg(long)]
    app: String,
    /// Label used as `scenario` in the JSON output.
    #[arg(long, default_value = "trace")]
    name: String,
    /// Optional ground-truth hangup time (seconds from trace start).
    /// Enables end_latency and early_end metrics.
    #[arg(long)]
    true_hangup_t: Option<f64>,
}

fn main() -> Result<()> {
    let args = Args::parse();
    let events = load_trace(&args.trace)?;
    let scenario = scenario_from_events(&args.name, &args.app, events, args.true_hangup_t);
    let metrics = run_scenario(&scenario);
    println!("{}", serde_json::to_string(&metrics)?);
    Ok(())
}
