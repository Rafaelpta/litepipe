//! `screenpipe debug` — one-shot diagnostic subcommands used to reproduce bugs
//! on a binary that has the right TCC permissions (Accessibility, Screen
//! Recording) without needing to run the full app. Grant the built binary AX
//! once via System Settings → Privacy & Security → Accessibility, then
//! individual probes run instantly with full permission.

use super::DebugCommand;

pub async fn handle_debug_command(subcommand: &DebugCommand) -> anyhow::Result<()> {
    match subcommand {
        DebugCommand::A11yWalk { app, settle_ms } => a11y_walk(app.as_deref(), *settle_ms).await,
    }
}

async fn a11y_walk(app_filter: Option<&str>, settle_ms: u64) -> anyhow::Result<()> {
    #[cfg(not(target_os = "macos"))]
    {
        let _ = (app_filter, settle_ms);
        anyhow::bail!("debug a11y-walk is macOS-only — the probe targets AXUIElement APIs");
    }

    #[cfg(target_os = "macos")]
    {
        use screenpipe_a11y::tree::{create_tree_walker, TreeWalkResult, TreeWalkerConfig};
        use std::time::{Duration, Instant};

        // 1. Identify the currently frontmost app via AX. If this fails the
        //    binary does not have Accessibility permission — surface an
        //    actionable message and bail out before doing more work.
        let (pid, app_name) = match focused_app_via_ax() {
            Ok(x) => x,
            Err(e) => {
                println!("\n❌ AX sys-wide query failed: {e}");
                println!("   Most likely cause: the binary at this path was not granted");
                println!("   Accessibility permission. Drag the binary into System Settings →");
                println!("   Privacy & Security → Accessibility and toggle it on.");
                println!("   Binary path: {}", std::env::current_exe()?.display());
                anyhow::bail!("Accessibility permission required");
            }
        };
        println!("focused_app via AX: pid={pid}, name={app_name:?}");

        // If a filter was provided, abort if the wrong app is frontmost.
        // No focus-stealing here — the user is expected to bring the target
        // app forward themselves so we don't interact with their layout.
        if let Some(filter) = app_filter {
            if !app_name.eq_ignore_ascii_case(filter) {
                println!("\n⚠  focused app is {app_name:?}, not {filter:?} — bring {filter} to the front and rerun.");
                return Ok(());
            }
        }

        // 2. Walk the tree 3×: immediately after a brief settle, then at
        //    +300ms and +1000ms. Chromium/Electron apps build their AX tree
        //    lazily; if the retry pattern shows growing text, the production
        //    fix is a post-flag sleep. If all three are empty, the hypothesis
        //    is different (AXManualAccessibility / pid mismatch / etc.).
        std::thread::sleep(Duration::from_millis(settle_ms));

        let walker = create_tree_walker(TreeWalkerConfig::default());
        let mut results: Vec<(u64, TreeWalkResult)> = Vec::with_capacity(3);

        let start = Instant::now();
        results.push((
            start.elapsed().as_millis() as u64,
            walker.walk_focused_window()?,
        ));

        std::thread::sleep(Duration::from_millis(300));
        results.push((
            start.elapsed().as_millis() as u64,
            walker.walk_focused_window()?,
        ));

        std::thread::sleep(Duration::from_millis(700));
        results.push((
            start.elapsed().as_millis() as u64,
            walker.walk_focused_window()?,
        ));

        println!("\n--- walk results ---");
        for (i, (elapsed, result)) in results.iter().enumerate() {
            let label = format!("walk {} (t+{}ms)", i + 1, elapsed);
            match result {
                TreeWalkResult::Found(snap) => {
                    // Line-capture stats: for each AXStaticText node, count how
                    // many had `lines` populated and how many were on-screen
                    // multi-line candidates that did NOT get lines (eligibility
                    // gap = AX call failure or budget exhaustion).
                    let mut static_text_total = 0usize;
                    let mut static_text_onscreen = 0usize;
                    let mut static_text_multiline_candidates = 0usize;
                    let mut nodes_with_lines = 0usize;
                    let mut total_lines: usize = 0;
                    let mut sample_lines_text: Option<String> = None;
                    for node in &snap.nodes {
                        if node.role != "AXStaticText" {
                            continue;
                        }
                        static_text_total += 1;
                        if node.on_screen == Some(true) {
                            static_text_onscreen += 1;
                        }
                        if let Some(b) = &node.bounds {
                            // Same heuristic as the walker uses to gate capture.
                            if node.on_screen == Some(true)
                                && screenpipe_a11y::tree::node_looks_multiline(&node.text, b, 1.5)
                            {
                                static_text_multiline_candidates += 1;
                            }
                        }
                        if let Some(lines) = &node.lines {
                            nodes_with_lines += 1;
                            total_lines += lines.len();
                            if sample_lines_text.is_none() {
                                let preview: String =
                                    node.text.chars().take(60).collect::<String>().replace('\n', " ↵ ");
                                sample_lines_text = Some(format!(
                                    "  └─ sample: {} lines on '{}…'",
                                    lines.len(),
                                    preview
                                ));
                            }
                        }
                    }
                    println!(
                        "{label:<25}  Found: app={:?} window={:?} nodes={} text_len={} truncated={}",
                        snap.app_name,
                        snap.window_name,
                        snap.node_count,
                        snap.text_content.len(),
                        snap.truncated,
                    );
                    println!(
                        "                              AXStaticText: {} total, {} on-screen, {} multi-line candidates",
                        static_text_total, static_text_onscreen, static_text_multiline_candidates,
                    );
                    println!(
                        "                              line capture: {} nodes with lines, {} total lines",
                        nodes_with_lines, total_lines,
                    );
                    if let Some(s) = sample_lines_text {
                        println!("                            {s}");
                    }
                    if !snap.text_content.is_empty() {
                        let preview = snap
                            .text_content
                            .chars()
                            .take(200)
                            .collect::<String>()
                            .replace('\n', " ↵ ");
                        println!("                              preview: {preview}");
                    }
                }
                TreeWalkResult::NotFound => {
                    println!(
                        "{label:<25}  NotFound — focused_window AX query failed (app has no focused window or denied)"
                    );
                }
                TreeWalkResult::Skipped(reason) => {
                    println!("{label:<25}  Skipped — {reason:?}");
                }
            }
        }

        // Quick verdict on the async-settle hypothesis. The text lengths across
        // the three walks tell us whether waiting helps.
        let lens: Vec<usize> = results
            .iter()
            .map(|(_, r)| match r {
                TreeWalkResult::Found(s) => s.text_content.len(),
                _ => 0,
            })
            .collect();
        println!("\n--- verdict ---");
        if lens.iter().all(|&l| l == 0) {
            println!("all three walks empty → async-settle is NOT the cause.");
            println!("likely next steps: try setting AXManualAccessibility, or verify the");
            println!("pid returned by AX (may be a helper-renderer process).");
        } else if lens[2] > lens[0] {
            println!(
                "text grew across retries ({} → {} → {}) → async-settle IS helping.",
                lens[0], lens[1], lens[2]
            );
            println!("production fix: add a short sleep after setting AXEnhancedUserInterface,");
            println!(
                "or keep the attribute set persistently so Chromium caches the enabled state."
            );
        } else {
            println!(
                "text populated on the first walk ({}) → AX works fine for this app.",
                lens[0]
            );
        }

        Ok(())
    }
}

#[cfg(target_os = "macos")]
fn focused_app_via_ax() -> anyhow::Result<(i32, String)> {
    use cidre::{ax, ns};
    let sys = ax::UiElement::sys_wide();
    let app = sys
        .focused_app()
        .map_err(|e| anyhow::anyhow!("sys_wide focused_app failed: {e:?}"))?;
    let pid = app
        .pid()
        .map_err(|e| anyhow::anyhow!("focused_app pid failed: {e:?}"))?;
    let name = ns::RunningApp::with_pid(pid)
        .and_then(|a| a.localized_name())
        .map(|s| s.to_string())
        .unwrap_or_default();
    Ok((pid, name))
}
