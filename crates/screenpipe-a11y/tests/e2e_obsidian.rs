//! E2E test for the macOS Obsidian (Electron) accessibility capture regression.
//!
//! See https://github.com/screenpipe/screenpipe/issues/3002 — captured frames
//! come back with `frames.app_name = ''` and OCR fallback runs at ~150% CPU
//! because the AX tree walker returns empty for Obsidian. These tests drive
//! the walker against a live Obsidian instance and assert which failure mode
//! we're actually hitting.
//!
//! **Run manually** (requires Obsidian installed, macOS AX permission granted
//! to the test binary, and single-threaded to avoid focus races):
//!
//! ```sh
//! cargo test -p screenpipe-a11y --test e2e_obsidian -- --test-threads=1 --nocapture --ignored
//! ```
//!
//! All tests are `#[ignore]` by default because they require a real user-installed
//! app + AX permissions that CI can't satisfy.

#[cfg(target_os = "macos")]
mod obsidian {
    use screenpipe_a11y::tree::{create_tree_walker, TreeWalkResult, TreeWalkerConfig};
    use std::path::Path;
    use std::process::Command;
    use std::time::{Duration, Instant};

    const OBSIDIAN_APP_PATH: &str = "/Applications/Obsidian.app";

    /// Run an AppleScript one-liner, returning trimmed stdout on success.
    fn applescript(script: &str) -> Result<String, String> {
        let output = Command::new("osascript")
            .arg("-e")
            .arg(script)
            .output()
            .map_err(|e| format!("osascript spawn failed: {}", e))?;
        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
        }
    }

    /// Skip with a clear message if Obsidian isn't installed. Returning `false`
    /// lets the caller `return` to mark the test as a no-op pass instead of a
    /// misleading failure on machines without Obsidian.
    fn obsidian_available() -> bool {
        if !Path::new(OBSIDIAN_APP_PATH).exists() {
            eprintln!("  [skip] Obsidian not installed at {OBSIDIAN_APP_PATH}");
            return false;
        }
        true
    }

    /// Bring Obsidian to the front and wait for it to become frontmost.
    /// Extra settle time after focus to give Chromium a chance to build its tree.
    fn activate_obsidian(settle_ms: u64) -> bool {
        let _ = applescript(r#"tell application "Obsidian" to activate"#);
        let deadline = Instant::now() + Duration::from_secs(5);
        while Instant::now() < deadline {
            if let Ok(front) = applescript(
                r#"tell application "System Events" to get name of first application process whose frontmost is true"#,
            ) {
                if front.eq_ignore_ascii_case("Obsidian") {
                    std::thread::sleep(Duration::from_millis(settle_ms));
                    return true;
                }
            }
            std::thread::sleep(Duration::from_millis(150));
        }
        eprintln!("  [warn] Obsidian never became frontmost within 5s");
        false
    }

    fn walker() -> Box<dyn screenpipe_a11y::tree::TreeWalkerPlatform> {
        create_tree_walker(TreeWalkerConfig::default())
    }

    /// Core regression: walk the tree once after Obsidian is focused and report
    /// exactly which branch we hit. This is the "single shot" reproduction of
    /// the bug — if text comes back non-empty here, the AX path is fine and
    /// the issue is elsewhere (caching, rate-limiting, pipeline).
    #[test]
    #[ignore]
    fn obsidian_walk_returns_non_empty_text() {
        if !obsidian_available() {
            return;
        }
        // Short settle — matches the production pipeline which walks almost
        // immediately after an AppSwitch trigger fires.
        if !activate_obsidian(150) {
            return;
        }

        let result = walker()
            .walk_focused_window()
            .expect("walk_focused_window should not hard-error");

        match result {
            TreeWalkResult::Found(snap) => {
                println!(
                    "  Found: app={:?}, window={:?}, nodes={}, text_len={}, walk={:?}, truncated={}",
                    snap.app_name,
                    snap.window_name,
                    snap.node_count,
                    snap.text_content.len(),
                    snap.walk_duration,
                    snap.truncated,
                );
                // First-level expectation: the walker identifies the app at all.
                assert_eq!(
                    snap.app_name, "Obsidian",
                    "walker returned Found but app_name is not 'Obsidian' — pid/RunningApp mismatch"
                );
                // Core regression assertion. Fails today on Electron/Obsidian.
                // When this fails, snap.node_count / snap.text_content.len()
                // printed above tell you which path: 0 nodes = AX children
                // missing; >0 nodes + 0 text = walker traversed but every node
                // had no value (Chromium not materializing leaf text).
                assert!(
                    !snap.text_content.is_empty(),
                    "Obsidian walk produced empty text (nodes={}). This is issue #3002. \
                     Hypothesis test: retry with longer settle — see `obsidian_walk_retries_after_settle`.",
                    snap.node_count
                );
            }
            TreeWalkResult::NotFound => panic!(
                "walker returned NotFound — focused_window AX query failed. \
                 Obsidian may have no window focused, or AX access is denied."
            ),
            TreeWalkResult::Skipped(reason) => panic!(
                "walker skipped Obsidian with reason={:?} — unexpected, \
                 Obsidian is not in the excluded/ignored list",
                reason
            ),
        }
    }

    /// Hypothesis probe: Chromium builds the AX tree asynchronously after
    /// `AXEnhancedUserInterface = true` is set on each walk. The first walk
    /// "primes" the tree; subsequent walks may return more content. If this
    /// holds, the production fix is to either (a) wait after setting the flag,
    /// or (b) keep the flag set once and not re-trigger on every walk.
    ///
    /// This test doesn't assert a pass/fail for the hypothesis — it prints the
    /// three measurements so we can compare. Fail only if all three walks
    /// return empty (then the async-settle theory is disproven and we need
    /// hypothesis 2: `AXManualAccessibility` or a different attribute).
    #[test]
    #[ignore]
    fn obsidian_walk_retries_after_settle() {
        if !obsidian_available() {
            return;
        }
        if !activate_obsidian(150) {
            return;
        }

        let walker = walker();
        let mut lens = Vec::new();
        let mut nodes = Vec::new();

        // Walk 1: immediate (mimics a trigger firing right after focus).
        let (len1, n1) = measure(&*walker);
        lens.push(len1);
        nodes.push(n1);
        println!("  walk 1 (t+0ms):    nodes={n1}, text_len={len1}");

        // Walk 2: after a short settle — enough for Chromium to push its
        // accessibility updates if it's on a frame-tick schedule.
        std::thread::sleep(Duration::from_millis(300));
        let (len2, n2) = measure(&*walker);
        lens.push(len2);
        nodes.push(n2);
        println!("  walk 2 (t+300ms):  nodes={n2}, text_len={len2}");

        // Walk 3: after a full second — enough for anything async.
        std::thread::sleep(Duration::from_millis(700));
        let (len3, n3) = measure(&*walker);
        lens.push(len3);
        nodes.push(n3);
        println!("  walk 3 (t+1000ms): nodes={n3}, text_len={len3}");

        // Actionable assertion: if at least one walk produced text, the bug is
        // async materialization. If none did, it's a deeper issue
        // (AXManualAccessibility required, pid mismatch, etc.).
        let any_content = lens.iter().any(|&l| l > 0);
        assert!(
            any_content,
            "all three walks returned empty text (lens={lens:?}, nodes={nodes:?}). \
             Async-settle hypothesis disproven — likely need AXManualAccessibility \
             or the walker is being handed the wrong pid (e.g. Obsidian Helper Renderer)."
        );

        // If settle helps, node counts / text lens should be non-decreasing.
        // This is informational, not enforced — user input (typing, cursor
        // movement) can shrink visible text between walks.
        if lens[0] < lens[2] {
            println!(
                "  async-settle hypothesis SUPPORTED: text grew from {} → {} over 1s",
                lens[0], lens[2]
            );
        }
    }

    fn measure(walker: &dyn screenpipe_a11y::tree::TreeWalkerPlatform) -> (usize, usize) {
        match walker.walk_focused_window() {
            Ok(TreeWalkResult::Found(snap)) => (snap.text_content.len(), snap.node_count),
            Ok(TreeWalkResult::NotFound) => (0, 0),
            Ok(TreeWalkResult::Skipped(_)) => (0, 0),
            Err(_) => (0, 0),
        }
    }

    /// Guard test: verify the PID returned by AX for Obsidian matches the main
    /// process, not a helper renderer. If this assertion fails it explains why
    /// `ns::RunningApp::with_pid` returns None and `app_name` ends up empty —
    /// hypothesis 3 from issue #3002.
    #[test]
    #[ignore]
    fn obsidian_focused_pid_is_main_process() {
        if !obsidian_available() {
            return;
        }
        if !activate_obsidian(150) {
            return;
        }

        use cidre::{ax, ns};
        let sys = ax::UiElement::sys_wide();
        let app = sys
            .focused_app()
            .expect("AX sys-wide focused_app should succeed");
        let pid = app.pid().expect("focused_app should have a pid");
        println!("  AX focused_app pid = {pid}");

        let running = ns::RunningApp::with_pid(pid);
        assert!(
            running.is_some(),
            "NSRunningApplication::with_pid({pid}) returned None — AX handed us a helper-process pid \
             (e.g. 'Obsidian Helper (Renderer)') that isn't registered as a runnable app. \
             Fix: walk the process tree to find the parent main-bundle process."
        );
        let name = running
            .unwrap()
            .localized_name()
            .map(|s| s.to_string())
            .unwrap_or_default();
        println!("  NSRunningApplication localized_name = {name:?}");
        assert_eq!(
            name, "Obsidian",
            "pid {pid} resolves to {name:?}, not 'Obsidian' — wrong process"
        );
    }
}
