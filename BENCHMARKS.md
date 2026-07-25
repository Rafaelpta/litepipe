# Benchmarks

> Status: draft, not for publication. These are stage one numbers, taken with
> the capture engine not running, on builds that are not yet notarized. They are
> kept here so the work is not lost. Do not quote or publish them until stage two
> (real recording under load on a signed build) is done.

This document reports a first, honest measurement of litepipe against stock
Screenpipe on the same machine. It covers what litepipe is meant to improve:
a smaller download, lower idle cost, and no traffic to remote servers. It is
transparent about where litepipe does not win yet, and about the limits of
this first round.

Numbers here are a starting point, not a marketing claim. The measurement
script and the raw output files are in this repository so anyone can rerun it
and check.

## Setup

Both apps were measured on one machine, back to back, each with its own fresh
data directory so each ran on its own defaults.

| Item | Value |
|------|-------|
| Machine | MacBookPro16,1 (Intel), macOS 26.5.2 |
| Stock build | Screenpipe 2.5.136 (current release at test time) |
| litepipe build | this repository, release build |
| Idle window | 300 seconds per app |
| Sampling | every 5 seconds |
| What is sampled | resident memory (RSS), CPU percent, and every remote endpoint the process talks to |

Raw output:

* `scripts/bench/results/stock-screenpipe-2.5.136.txt`
* `scripts/bench/results/litepipe.txt`

## Results at a glance

| Metric (idle) | Stock Screenpipe | litepipe | Read |
|---------------|------------------|----------|------|
| Install size on disk | 375 MB | 289 MB | litepipe is 86 MB smaller (about 23 percent) |
| CPU, average | 5.2 percent | 0.6 percent | litepipe is about 9 times lower |
| CPU, peak | 8.3 percent | 1.9 percent | litepipe stays near zero |
| Remote endpoints contacted | 4 | 0 | litepipe talks to nothing outside the machine |
| Resident memory (RSS) | about 290 MB | about 380 MB | litepipe uses more here, see the note below |

## What each result means

### Install size: 289 MB vs 375 MB

litepipe ships 86 MB less. The removed weight is the account and cloud layer,
the hosted AI runtime, the updater, and the connections stack. Smaller download,
less to trust, less to keep current.

### Idle CPU: 0.6 percent vs 5.2 percent

Sitting still and doing nothing, stock Screenpipe averaged 5.2 percent CPU and
peaked at 8.3 percent. litepipe averaged 0.6 percent and peaked at 1.9 percent,
roughly 9 times lower. The stock number is not the capture engine working, it
is background machinery: telemetry, health polling, update checks, and the
attribution and analytics loops. litepipe removes all of that, so an idle app
is actually idle.

### Remote endpoints: 0 vs 4

Over the 300 second idle window, stock Screenpipe opened connections to four
external endpoints on port 443, including one plain IPv4 host and Amazon
hosted IPv6 addresses. litepipe opened zero. Its only listening socket is on
`127.0.0.1`, the machine itself. This is the core promise of litepipe, and it
held under the stricter per sample detector used for the litepipe run.

### Resident memory: about 380 MB vs about 290 MB

This is the one number where litepipe does not win in this round. At idle
litepipe held about 90 MB more resident memory than stock. Two things are worth
stating plainly:

1. In both runs the capture engine (the local server on port 3030) did not come
   up. These builds are not notarized, so macOS did not grant screen recording,
   and the engine never started. So this compares the app window and its web view
   at rest, not the capture path.
2. The most likely reason litepipe holds more memory at rest is that it boots
   straight into the full local interface, because the login and onboarding gate
   was removed, while the stock build sits on a lighter pre login screen. In
   other words litepipe has more of the real app loaded and ready. We did not
   isolate this precisely, so we report the raw number and leave the claim
   modest. Memory is a target for a later round, not a win to claim today.

## Limitations

Read these before quoting any number.

* Different generations. The stock build is 2.5.136. litepipe forks from the
  last MIT licensed commit, which is older. Some difference reflects months of
  upstream change, not only what litepipe removed.
* Idle only. This round measures the app at rest. It does not yet measure the
  capture path under load: CPU and disk while actually recording screen and
  audio. That is the number that matters most for a capture tool, and it needs
  the engine running, which needs a notarized build. It is planned as a second
  round once code signing is in place.
* One machine, one operating system. Results were taken on a single Intel Mac.
  Apple silicon and other systems may differ.
* Endpoint counts are a lower bound. The detector samples open sockets, so a
  very brief connection between samples can be missed. This can only undercount
  the stock number, never inflate it.

## Reproduce it

The script is `scripts/bench/measure.sh`. It takes a label, a pattern that
matches the app process, and a duration in seconds.

```bash
# stock
bash scripts/bench/measure.sh screenpipe "Screenpipe.app/Contents/MacOS" 300

# litepipe
bash scripts/bench/measure.sh litepipe "litepipe.app/Contents/MacOS" 300
```

Run each app on a fresh data directory, one at a time, since both share the same
local port and data path. Compare the two output files.
