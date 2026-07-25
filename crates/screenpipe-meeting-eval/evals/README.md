# Meeting-detection eval harness

Replays scripted scan traces through the prod meeting-detection state
machine (`screenpipe_engine::meeting_detector::advance_state`) and
scores meeting count, flap count, and end-latency against
per-scenario expectations.

## Why this exists

The state machine has accreted ~60 commits of edge-case fixes
(Zoom-idle false starts, Discord-browser Mute always-visible, Arc
tab-switch grace, audio-output extension, …) with no end-to-end
regression coverage of **state transitions over time**. The
Active⇌Ending flap bug from 2026-05-11 (Meeting 72 + 73 in Arc) is
invisible to existing unit tests because each test calls
`advance_state` once. This crate exists to make that class of bug
visible and to keep historical fixes from rotting.

## What it tests

Layer 3 only — the pure state machine. Two adjacent layers are out of
scope here:

- **Layer 1 — signal matching:** already covered by 110+ unit tests
  inside `meeting_detector.rs`.
- **Layer 2 — AX-tree scanning:** future work. Plan is a
  redacted-AX-tree fixture format + a `scan_process` replayer; see
  the crate-level docstring on `src/lib.rs`.

## How to run

```bash
# all seed scenarios
cargo run --release -p screenpipe-meeting-eval --bin screenpipe-eval-meeting-state -- \
  crates/screenpipe-meeting-eval/evals/scenarios/*.toml

# unit tests (includes embedded scenarios)
cargo test -p screenpipe-meeting-eval
```

Each scenario emits one JSON line on stdout. The CLI exits non-zero
if any non-`xfail` scenario fails its expectations. Pass `--no-gate`
to disable.

## Scenario format

```toml
[meta]
name = "..."
description = "..."
app = "Arc"               # ScanResult.app_name; determines is_browser
scan_interval_seconds = 5.0   # matches prod ACTIVE_SCAN_INTERVAL

# Tick specs — each expands into zero or more (t, in_call) ticks.
# Types: "single", "constant", "flap".

[[ticks]]
type = "single"
t = 5
in_call = true

[[ticks]]
type = "constant"
from = 10
to = 600
in_call = true

[[ticks]]
type = "flap"             # alternating visible/hidden — models toolbar auto-hide
from = 10
to = 2700
visible_seconds = 27
hidden_seconds = 8

# Optional: timestamps where output audio is flowing.
# Triggers the audio-extension branch in `advance_state` when in Ending.
[[audio_ranges]]
from = 5
to = 1800

[expected]
true_hangup_t_seconds = 1800   # used to compute end_latency / early_end
meeting_count = 1
final_state = "Idle"
flap_count_max = 5
end_latency_seconds_max = 360
early_end_max = 0

# Optional: declare an in-flight bug. Test reports it but doesn't gate
# on it. Flip off once the fix lands — this then becomes a regression
# test.
[xfail]
reason = "..."
```

## Metrics

```json
{
  "scenario": "arc_meet_toolbar_autohide",
  "meeting_starts": 1,
  "meeting_ends": 0,
  "final_state": "Active",
  "flap_count": 77,
  "flap_count_controls": 77,
  "flap_count_audio": 0,
  "end_latency_seconds": null,
  "early_end_count": 0,
  "total_ticks": 542,
  "xfail": "Toolbar auto-hide flap bug; hysteresis fix not yet landed",
  "assertion_failures": [
    "meeting_count: want 1 got 1",
    "final_state: want \"Idle\" got \"Active\"",
    "flap_count: max 3 got 77"
  ]
}
```

Fields:

- **meeting_starts / meeting_ends** — number of `StartMeeting` /
  `EndMeeting` actions the state machine fired.
- **final_state** — `Idle` | `Confirming` | `Active` | `Ending`.
- **flap_count** — Ending → Active transitions inside a single
  meeting (combined). Split into `flap_count_controls` (controls
  reappeared) and `flap_count_audio` (audio still flowing). High
  controls-flap = brittle detection. High audio-flap = legitimate,
  but track for drift.
- **end_latency_seconds** — wall-clock between user's true hang-up
  (`expected.true_hangup_t_seconds`) and the `EndMeeting` firing.
  `null` if neither side declared.
- **early_end_count** — `EndMeeting` actions that fired before the
  user actually hung up. Should always be 0.
- **assertion_failures** — list of expectations that didn't match.

## Seed scenarios

| scenario | what it guards |
|---|---|
| `zoom_native_clean_call.toml` | Happy path: native Zoom, controls visible, clean hang-up. Baseline. |
| `confirming_drops_no_meeting.toml` | Transient false-positive signal does not create a meeting (Confirming → Idle on timeout). |
| `browser_tab_switch_with_audio.toml` | Regression for `be6a6f148`/`d8ba1dad3`: tab switch hides controls, audio keeps Active. One meeting, not many. |
| `native_zoom_minimized_with_audio.toml` | Regression for `4e784f620` (#2536): native app minimized, audio keeps it alive. |
| `arc_meet_toolbar_autohide.toml` | **XFAIL** — Meeting 72/73 (2026-05-11): Arc Meet toolbar auto-hide causes Active⇌Ending flap. Flip off when hysteresis ships. |

## Replaying real traces

`screenpipe-eval-meeting-replay-trace` consumes a JSONL trace — one
`{t, in_call, has_audio?}` per line — and feeds it through the same
state machine the TOML scenarios use:

```bash
cargo run --release -p screenpipe-meeting-eval --bin \
  screenpipe-eval-meeting-replay-trace -- \
  crates/screenpipe-meeting-eval/evals/traces/meeting72_arc_real.jsonl \
  --app Arc --name meeting72 --true-hangup-t 4254
```

This emits the same JSON metrics shape as the TOML path, so a real
log replay can be diffed against any hand-written scenario.

### The Meeting 72 trace

`evals/traces/meeting72_arc_real.jsonl` is extracted from
`~/.screenpipe/screenpipe-app.2026-05-11.log` — the user's 70-minute
Google Meet call in Arc that triggered the bug investigation.
Replaying it through today's state machine reproduces:

```json
{"scenario":"meeting72","meeting_starts":1,"meeting_ends":0,
 "final_state":"Ending","flap_count":23,"flap_count_controls":23,
 "end_latency_seconds":null}
```

23 control-flaps, never naturally ended — confirms the bug shape
from production data. Once the fix lands and we re-extract a
post-fix log, this same replay should produce
`flap_count_controls ≤ 3, final_state="Idle", end_latency≈300s`.

### Uptime caveat

The harness backdates `Instant::now()` to drive `advance_state` on
simulated time. That means the process needs uptime ≥ scenario
length. TOML scenarios are capped at ~600s for cold-boot CI safety.
The Meeting 72 trace is 4254s — fine on a dev box (hours of uptime)
but it'll panic on a freshly-booted CI runner. Treat the replay
binary as a dev/investigation tool; CI gates the short TOML
scenarios only.

## Recording real traces (future)

To grow coverage from real usage without leaking content, add a
debug-build trace dumper to `run_meeting_detection_loop` that
appends one JSON line per scan to `~/.screenpipe/meeting_traces/`.
Only canonical signal types should be recorded — never raw AX node
names, URLs, or window titles. The user can then share a trace
file; it replays through `advance_state` to reproduce exactly what
the state machine saw. Tracked as a follow-up; see `src/lib.rs`
crate doc.
