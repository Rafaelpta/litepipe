# Contributing

litepipe is early and small on purpose. Bug reports with reproduction steps are
the most useful contribution right now.

Ground rules for pull requests:

* Keep the app fully local. Nothing may contact a remote server at boot or
  during normal use; the only allowed traffic is to the local engine on
  127.0.0.1 and to endpoints the user explicitly configured (their own AI
  provider, their own ICS calendar URL).
* No telemetry, no analytics, no crash reporting.
* Keep it lean. New background work needs a strong reason.
* Run the checks before sending: `tsc --noEmit` and `vitest run` in
  `apps/screenpipe-app-tauri`, and `cargo check` at the repo root.

By contributing you agree that your contributions are licensed under the MIT
license of this repository.
