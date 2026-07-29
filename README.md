<div align="center">

<img src="docs/assets/litepipe-icon.png" width="72" alt="litepipe" />

# litepipe

**The open source local memory of your work.**

[Features](#features) | [Install](#install) | [How it works](#how-it-works) | [Architecture](#architecture) | [FAQ](#faq)

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](#install)
[![Status](https://img.shields.io/badge/status-beta-orange.svg)](#status)

</div>

---

<!-- demo GIF goes here: banner "Transcribe this meeting?" appears over a call,
     click Yes, notch panel shows Transcribing meeting, transcript opens at the end.
     Caption: litepipe asks before it records. One click, and the meeting becomes
     a transcript on your disk. -->

You work all day and your AI still has the context of almost none of it.

litepipe keeps a local memory of everything you do, hear, and see on your
computer: the videos you watch, the meetings you join, the clicks and the work
across your apps, and stores it in one folder on your Mac.

litepipe is fully local. The only network socket in litepipe is the app talking
to its own engine on 127.0.0.1.

All data stays on your machine, in a local folder.

## Features

* **Meetings become transcripts.** litepipe spots the call window and asks. One
  click, and the transcript is on your disk when the call ends.
* **The microphone opens only for meetings you accept.** The recording is
  deleted once it has become text.
* **Everything on screen is captured.** Text comes from the accessibility tree,
  the layer assistive technology reads, with OCR for what the tree cannot see.
* **Nothing leaves the Mac.** Whisper and pyannote run on device, and the only
  socket is the app talking to its own engine.
* **One folder holds it all.** SQLite with full text search, so your agent reads
  it directly.

## Install

litepipe ships as a signed and notarized DMG: drag to Applications, open, and
the onboarding walks through the permissions.

Building from source needs Xcode:

```bash
git clone https://github.com/Rafaelpta/litepipe
cd litepipe/apps/litepipe-mac
./build-app.sh release
```

The capture engine ships prebuilt inside the app bundle; rebuilding it needs
Rust and CMake, see the engine crate under `crates/`.

## How it works

The engine reads the text of whatever you are working on through the
accessibility tree, the layer assistive technology uses: like HTML, for every
app. OCR fills the gaps the tree cannot see, such as video, games, and remote
desktops. Audio goes through voice activity detection, is transcribed locally
with Whisper, and grouped by speaker. Everything lands in SQLite with full text
search.

The result is your work in a form software can use: query it, search it, or
point your AI agent at the folder and ask what you agreed to, planned, or
missed.

| Step | Detail |
|------|--------|
| Meeting detection | Window titles plus browser URLs from captured frames; banner within about 10 seconds of joining, mic on about 3 seconds after you accept |
| Capture | Event driven: an app switch, click, scroll stop, or typing pause triggers a screenshot paired with the accessibility tree; idle fallback when nothing happens; audio in 30 second chunks with 2 second overlap |
| Transcription | Whisper large v3 turbo (quantized, Metal) retranscribes the meeting after the call on audio normalized to -16 LUFS; transcript ready about 11 minutes after the call ends |
| Cleanup | Voice audio deleted after transcription, within the hour; system audio kept 7 days; frames 30 days; text and index kept |

## Privacy controls

Capture is not all or nothing. What ships today:

* **Private windows are never captured.** Safari, Chrome, Edge, Brave, Arc, and
  Firefox, with nothing to configure.
* **Password managers are never captured.** 1Password, Bitwarden, LastPass,
  Dashlane, KeePassXC, and Keychain Access.
* **Any app or site can be excluded.** Settings, Privacy takes the list, and an
  excluded window never reaches the capture buffer, so no frame and no text of
  it exists.
* **Capture stops when you want.** One shortcut pauses everything, hours can be
  restricted to a schedule, and DRM video pauses it on its own.
* **Secrets are redacted.** On by default: keys, cards, and passwords become
  labels in text and black boxes in screenshots, and the original is
  overwritten. Under the hood: 46 deterministic patterns run first (credit
  cards, private keys, database URLs carrying credentials, API keys for Stripe,
  OpenAI, Anthropic, Google, GitHub and more), an ONNX model on the Apple Neural
  Engine catches what patterns cannot, and a second model finds secrets in the
  pixels and paints those regions solid black rather than blurred, since a blur
  can be undone.
* **What was captured can be deleted.** One call to the local API removes the
  frames, audio, text, and files of a time range.
* **The whole memory can be locked.** The vault encrypts database and media with
  a key derived from your password, held only on your machine.

## Architecture

| Component | Stack | Role |
|-----------|-------|------|
| litepipe.app | Swift, AppKit, SwiftUI | Notch companion, meeting detection and consent, mic gate, timeline, settings |
| engine | Rust | Screen and audio capture, VAD, transcription, diarization, redaction, SQLite, local HTTP API |

The app spawns the engine as a child process and stays the TCC responsible
process, so one set of permissions covers both. Control flows over a loopback
HTTP API authenticated with a per install key. Data lives in `~/.litepipe`: a
SQLite database, media files, and logs you can open, back up, or delete.

```mermaid
flowchart LR
    SRC["Screen, screen text,<br/>system audio, UI events"] --> GATE
    MIC["Microphone<br/>accepted meetings only"] --> GATE
    GATE{"Guardrails"}
    GATE -->|"excluded"| DROP["Never written"]
    GATE -->|"allowed"| PROC["Whisper, speakers,<br/>redaction, retention"]
    PROC --> DISK[("~/.litepipe<br/>SQLite, frames, audio")]
    DISK --> API["Local API<br/>127.0.0.1:3030"] --> APP["litepipe.app"]
    DISK --> AGENT["Your AI agent"]
```

## The fork, in specs

Screenpipe built the hard part: a full day of screen and audio turned into
searchable text on a laptop, with the accessibility tree doing the heavy
lifting, published under MIT.

litepipe exists to keep that engine in the open and evolving. Pipes, accounts,
telemetry, and cloud sync are not here. All the work goes into less weight, less
latency, and more guardrails on what the engine captures.

| Kept (the core) | Removed (the platform) |
|-----------------|------------------------|
| Accessibility tree text extraction, OCR fallback, ScreenCaptureKit capture | Accounts and subscriptions |
| Local transcription: VAD, Whisper, Parakeet, speaker embeddings | Telemetry, crash reporting, auto update |
| SQLite storage, FTS5 search, local HTTP API | Cloud sync, hosted AI models, provider presets |
| Meeting detection and the retranscription pass | The pipe store and its schedulers |
| New: native Swift notch app replacing the Tauri shell | The web view shell |

Every removal serves the same goal: an app that stays idle until you ask it
something, with all data on your machine.

Bugs in the shared code go back to Screenpipe:
[issue 5531](https://github.com/screenpipe/screenpipe/issues/5531) and
[pull request 5532](https://github.com/screenpipe/screenpipe/pull/5532) fix
private browser windows being captured on macOS.

## Specs

| Area | Spec |
|------|------|
| Screen capture | ScreenCaptureKit, event driven: captures when the screen changes, idle fallback when it does not; all monitors, every on screen app |
| Screen text | Accessibility tree extraction; OCR fallback for video, games, remote desktops |
| Audio capture | System audio continuous; microphone only during confirmed meetings; 30 second chunks with 2 second overlap |
| Meeting detection | Zoom, Google Meet, Microsoft Teams (native and web), FaceTime; window titles plus browser URLs from captured frames; banner within about 10 seconds |
| Meeting end | Automatic about 30 seconds after the meeting windows disappear; stop button; shortcut |
| Transcription | Whisper large v3 turbo, quantized, Metal; audio normalized to -16 LUFS; full meeting context; transcript about 11 minutes after the call ends |
| Speaker separation | pyannote segmentation and voice embeddings |
| Secret redaction | On by default; 46 deterministic patterns plus ONNX models on the Apple Neural Engine (text and image); labels in text, solid black boxes in screenshots, source overwritten |
| Capture exclusions | Private browser windows, password managers, and the app and domain lists from Settings; excluded windows never reach the capture buffer |
| Storage | SQLite with FTS5 at `~/.litepipe/db.sqlite`; media in `~/.litepipe/data` |
| Retention | Voice audio deleted after transcription, within the hour; system audio 7 days; frames 30 days; text and index kept |
| Local API | REST on 127.0.0.1:3030 with a per install key; the same API the app uses |
| Telemetry | Disabled; the engine logs "telemetry is disabled" at startup |
| Offline | Fully functional without network after the one time model download on first run |
| Diagnostics | Engine lifecycle log at `~/.litepipe/app.log` |
| Distribution | Developer ID, hardened runtime, notarized, stapled DMG (69 MB); installed app about 230 MB |
| Platform | macOS on Apple Silicon |
| License | MIT, full source |

## FAQ

<details>
<summary>Does any audio or screen data leave my machine?</summary>

No. The engine downloads its models once on first run: Whisper and a voice
activity model for transcription, and two redaction models (54 MB for images,
278 MB for text) while secret redaction is on. After that, the only network
socket in the product is the app talking to its own engine on 127.0.0.1. There
is no telemetry, no crash reporting, and no updater.
</details>

<details>
<summary>What happens to the recording of my voice?</summary>

It is deleted after transcription, on the next cleanup pass, within the hour.
The transcript is kept. A voice recording is the most sensitive file on the disk
(minutes of audio are enough to clone a voice) and also the largest: an hour of
meetings is about 25 MB of audio and about 50 KB of transcript. The transcript
keeps the content; deleting the recording removes the risk and the bulk.
</details>

<details>
<summary>Which meeting apps are detected?</summary>

Zoom, Google Meet, and Microsoft Teams, both native apps and web clients, plus
FaceTime. Detection uses window titles and the browser URLs present in captured
frames.
</details>

<details>
<summary>How much disk does it use?</summary>

System audio is kept 7 days and screen frames 30 days, both reclaimed
automatically. Text and the search index are kept and are small.
</details>

<details>
<summary>Can my AI agent read the data?</summary>

Yes. Everything is plain SQLite and media files in `~/.litepipe`. Point an agent
at the folder and query it.
</details>

<details>
<summary>How do I keep something out of the memory?</summary>

Four ways. A private browser window is skipped automatically, in every browser.
Any app or domain can be added to the ignore list in Settings, Privacy. The
shortcut pauses all capture instantly. And if something was captured anyway, one
call to the local API deletes everything in a time range, files included.
</details>

<details>
<summary>Is the data encrypted?</summary>

The disk is covered by FileVault, which macOS enables by default. On top of
that, litepipe ships a vault: a password lock that encrypts the database and all
media with a key derived from your password, held only on your machine. The
vault locks data at rest; transparent encryption during capture is on the
roadmap.
</details>

<details>
<summary>How do I delete everything?</summary>

Quit the app and delete `~/.litepipe`.
</details>

## Status

Early beta. Native macOS on Apple Silicon. Open an issue when something breaks.

The engine binary in the app predates that fix, so private browsing is excluded
by window title until the next engine build.

## Contributing

Bug reports and fixes are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) covers the
scope, how to report a bug without pasting your captured data, and the rule
about not importing Screenpipe code from after the relicense.

## License

litepipe incorporates open source code from Screenpipe, used under the MIT
license and preserved in [NOTICE](NOTICE) and [LICENSE.md](LICENSE.md).
