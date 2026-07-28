<div align="center">

# litepipe

**A local memory of everything you see and hear. Recorded, transcribed, and searchable, entirely on your own machine.**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](#build-from-source)
[![Status](https://img.shields.io/badge/status-early-orange.svg)](#status)

</div>

---

litepipe runs quietly in the background and keeps a searchable record of what
crossed your screen and what was said around you. Ask it what a client agreed to
last Tuesday, pull the exact wording of a message you closed an hour ago, or hand
a meeting to a local model and get the summary back. Everything is captured,
transcribed, and stored on your computer, and none of it leaves.

Most tools in this space are built the other way around. They open with a sign in
screen, send usage home, check for updates, and lean on a hosted service for the
parts that cost money. litepipe takes the opposite stance: no account, no
telemetry, no cloud. The app you install is the whole app, and it answers only to
you.

## What it does

* **Captures your screen** through the accessibility tree, with OCR as a fallback
  for anything the tree cannot read, such as video, games, and remote desktops.
* **Transcribes audio** locally with Whisper, and separates speakers so you can
  search by who said what.
* **A timeline** you can scroll and rewind, frame by frame, across your whole day.
* **Full text search** over everything on screen and everything spoken.
* **Meeting notes** detected automatically, with attendees and a place for your
  own notes.
* **Memories**, the high signal facts and decisions distilled out of the raw
  stream, so the important things stay easy to find.
* **Chat** over your own history, running against a local model or your own key.

## How litepipe is set up

Every part of the app is built around one rule: the data stays on the machine.

| Area | How litepipe handles it |
|------|-------------------------|
| Network | Nothing leaves the computer. No analytics, no crash reporting, no updater, no attribution ping. The only socket is between the app and its own engine on `127.0.0.1`. |
| Accounts | None. No sign in, no subscription, no paywall. The app opens straight into the product. |
| Disk | Retention is on by default. Old video and audio are reclaimed after 30 days while the text, the search index, and the timeline history are kept. Your disk does not quietly fill up. |
| Background work | Quiet at rest. The suggestion schedulers, calendar pollers, and cloud sync workers that usually run at boot are gone, so an idle app is actually idle. |
| AI | Yours. Chat runs against local Ollama or any OpenAI or Anthropic compatible endpoint with your own key. There is no hosted provider and no default that phones anywhere. |

## Why local matters

**Privacy.** A record of your screen and your conversations is about as sensitive
as data gets. The safest place for it is the one machine you control, and the
safest amount to send anywhere else is none.

**Cost.** No subscription, no per seat pricing, no metered API in the middle. If
you already run a local model, running litepipe costs you nothing but disk.

**Ownership.** Your history is a plain SQLite database and media files in a folder
you can open, back up, or delete. Nothing is locked behind a service that can
change its terms or disappear.

**Quiet by default.** Because the background machinery is gone, litepipe sits
close to idle when you are not asking it anything.

## How it works

1. A capture engine records screen frames and microphone audio.
2. Screen text is read from the accessibility tree, with OCR filling the gaps.
3. Audio is transcribed locally and grouped by speaker.
4. Everything lands in a local SQLite database and a search index on your disk.
5. The app reads that data back for the timeline, search, meetings, and memories.
6. Chat sends the relevant slice of your history to the model you chose, local or
   your own key, and nowhere else.

The engine listens only on `127.0.0.1`. The app talks to it there. That loop is
the entire network footprint.

## Status

Early. macOS is the primary target today. Windows and Linux build but get less
testing. Expect rough edges, and please open an issue when you hit one.

## Build from source

Requirements: Rust (stable), Bun, CMake, and on macOS a recent Xcode.

```bash
git clone https://github.com/Rafaelpta/litepipe
cd litepipe/apps/screenpipe-app-tauri
bun install
bun run tauri build
```

The bundle lands in `src-tauri/target/release/bundle/`.

On macOS, screen recording permission is strict about apps that are not
notarized. An unsigned local build can be granted the permission by hand in
System Settings, but if it does not stick, sign the build with your own identity.

## Benchmarks

litepipe is being measured against the stock build for install size, idle cost,
and network activity, on the same machine. The method and the raw output live in
[BENCHMARKS.md](BENCHMARKS.md). Those figures are still a draft. The number that
matters most for a capture tool, the cost while it is actually recording, needs a
signed build and is not published yet.

## Provenance and license

litepipe incorporates open source code from Screenpipe, used under the MIT
license and preserved in [NOTICE](NOTICE) and [LICENSE.md](LICENSE.md).
