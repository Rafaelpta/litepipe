//
// Standalone probe: exercise TinfoilRedactor against the live enclave
// and print the full reqwest error chain when something goes wrong.
//
// Run:
//   cargo run --example tinfoil_probe -p screenpipe-redact

use screenpipe_redact::{adapters::tinfoil::TinfoilRedactor, Redactor};

#[tokio::main]
async fn main() {
    let r = TinfoilRedactor::from_env();
    println!("[probe] has_auth = {}", r.has_auth());

    // Mix of short, medium, and "real OCR-shaped" payloads to see if
    // length is what's bumping the worker past the 8s client timeout.
    let realistic_long = "Marcus Chen <marcus@helios-ai.io> · 415-555-0142 · ".repeat(40);
    let payloads = [
        "hi".to_string(),
        "Email me at alice@example.com or call 415-555-0142.".to_string(),
        "Marcus Chen pushed the prod creds to the screenpipe/widget repo on slack.".to_string(),
        realistic_long,
    ];
    for (i, text) in payloads.iter().enumerate() {
        println!("\n[probe] sending #{i} (len={})…", text.len());
        let t0 = std::time::Instant::now();
        match r.redact(text).await {
            Ok(out) => println!(
                "  ok ({:.0}ms) → {:?}",
                t0.elapsed().as_secs_f64() * 1000.0,
                if out.redacted.len() > 100 {
                    format!("{}…", &out.redacted[..100])
                } else {
                    out.redacted.clone()
                }
            ),
            Err(e) => {
                let mut chain = format!("{}", e);
                let mut src: Option<&dyn std::error::Error> = std::error::Error::source(&e);
                while let Some(s) = src {
                    chain.push_str("\n           caused by: ");
                    chain.push_str(&s.to_string());
                    src = s.source();
                }
                println!("  ERR → {}", chain);
            }
        }
    }
}
