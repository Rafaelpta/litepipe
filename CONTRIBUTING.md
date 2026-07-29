# Contributing

litepipe keeps the capture engine Screenpipe published under MIT in the open and
evolving. Work that makes it lighter, faster, or better behaved with the user's
data is welcome. The project is early, so a bug report with reproduction steps
is already a real contribution.

## Scope

Open an issue first for anything beyond a small fix. It saves you from building
something that does not belong here.

In scope: capture quality, transcription quality, latency, memory and disk use,
privacy guardrails, the native macOS app, packaging, documentation.

Out of scope: accounts, subscriptions, telemetry, crash reporting, auto update,
cloud sync, hosted models, and anything that opens a network socket other than
the app talking to its own engine on 127.0.0.1, or an endpoint the user
configured themselves. These were removed on purpose.

## The upstream boundary

litepipe was forked at commit 24d3c2551d9b of 2026-06-10, the last Screenpipe
commit published under the MIT license. Screenpipe moved to a commercial license
later that same day.

Never copy, port, or cherry pick Screenpipe code committed on or after that
point, not even a fix you wrote yourself and sent them. Write it against this
tree instead. See NOTICE.

Bugs in the shared engine code are worth reporting to Screenpipe as well. That
is how [issue 5531](https://github.com/screenpipe/screenpipe/issues/5531) and
[pull request 5532](https://github.com/screenpipe/screenpipe/pull/5532) went.

## Reporting a bug

Include the macOS version, whether the app or a manual engine run was involved,
and the relevant lines from `~/.litepipe/app.log` (app and engine lifecycle) or
`~/.litepipe/engine-app.log` (engine output).

Never paste captured content into an issue: no transcripts, no OCR text, no rows
from `db.sqlite`, no screenshots of the timeline. Describe the shape of the
problem instead. If reproducing it needs data, build a synthetic case.

## Building

The app is Swift and needs Xcode:

```bash
git clone https://github.com/Rafaelpta/litepipe
cd litepipe/apps/litepipe-mac
swift build
./build-app.sh release
```

The capture engine ships prebuilt inside the app bundle. Rebuilding it needs
Rust and CMake, and the full Xcode toolchain rather than the command line tools:

```bash
cargo build --release -p screenpipe-engine
cargo test -p screenpipe-a11y
```

## Pull requests

One topic per pull request. Say what you changed, why, and how you tested it. A
regression test is the best argument a fix can carry.

Commit subjects are lowercase and scoped, for example
`fix(mac): quality pass boosts all recent mic chunks`.

By contributing you agree that your work is licensed under the MIT license, the
same terms as the rest of this repository.
