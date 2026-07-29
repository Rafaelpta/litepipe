# Contributing

The project is early, so a bug report with reproduction steps is already a real
contribution. Open an issue before writing anything beyond a small fix.

**Never paste captured content into an issue.** No transcripts, no OCR text, no
rows from `db.sqlite`, no screenshots of the timeline. Describe the problem, and
attach the relevant lines from `~/.litepipe/app.log` if they help.

**Never bring in Screenpipe code from after the relicense.** litepipe was forked
at commit `24d3c2551d9b` of 2026-06-10, the last one published under MIT; they
moved to a commercial license later that day. Write the fix against this tree
instead, and send it to them separately if it belongs there too. See
[NOTICE](NOTICE).

**Out of scope by design:** accounts, telemetry, crash reporting, auto update,
cloud sync, hosted models, and anything that opens a network socket other than
the app talking to its own engine on 127.0.0.1.

Building the app needs Xcode:

```bash
cd apps/litepipe-mac && swift build && ./build-app.sh release
```

The engine ships prebuilt in the bundle; rebuilding it needs Rust, CMake, and
the full Xcode toolchain.

One topic per pull request, and say how you tested it. Contributions are MIT,
like the rest of the repository.
