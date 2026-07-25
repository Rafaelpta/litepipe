#!/bin/bash
# Measure an app's FULL process tree footprint: memory, CPU, and every unique
# non-loopback endpoint the tree talks to (with reverse-DNS best effort).
#
# Usage: ./measure.sh <label> <root-cmd-pattern> <duration-seconds> [outdir]
#   root-cmd-pattern: regex matched against command lines to find the app's
#                     root process(es); the whole descendant tree is measured.
set -u
LABEL="${1:?label}"; PATTERN="${2:?pattern}"; DURATION="${3:?seconds}"; OUTDIR="${4:-$HOME/bench-results}"
mkdir -p "$OUTDIR"; TS=$(date +%Y%m%d-%H%M%S); OUT="$OUTDIR/${LABEL}-${TS}.txt"; REM="$OUTDIR/.${LABEL}-${TS}.rem"; : > "$REM"

roots() { ps ax -o pid=,command= | grep -E "$PATTERN" | grep -vE "measure|grep -E" | awk '{print $1}'; }
descendants() { # print pid + all descendants
  local q="$1" all="$1"
  while [ -n "$q" ]; do
    local next=""
    for p in $q; do
      local c; c=$(pgrep -P "$p" 2>/dev/null | tr '\n' ' ')
      next="$next $c"; all="$all $c"
    done
    q=$(echo $next | xargs -n1 2>/dev/null | sort -u | tr '\n' ' ')
    [ -z "$(echo $q | tr -d ' ')" ] && break
  done
  echo $all | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -un
}

{ echo "label: $LABEL"; echo "pattern: $PATTERN"; echo "duration_s: $DURATION"
  echo "host: $(sysctl -n hw.model 2>/dev/null) / macOS $(sw_vers -productVersion 2>/dev/null)"
  echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo
  echo "== samples (5s): epoch procs rss_mb cpu_pct =="; } > "$OUT"

END=$(( $(date +%s) + DURATION ))
while [ "$(date +%s)" -lt "$END" ]; do
  R=$(roots); TREE=""
  for r in $R; do TREE="$TREE $(descendants "$r")"; done
  TREE=$(echo $TREE | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -un)
  if [ -n "$TREE" ]; then
    N=$(echo "$TREE" | wc -l | tr -d ' ')
    RKB=$(echo "$TREE" | xargs -I{} ps -o rss= -p {} 2>/dev/null | awk '{s+=$1} END{print s+0}')
    CPU=$(echo "$TREE" | xargs -I{} ps -o %cpu= -p {} 2>/dev/null | awk '{s+=$1} END{printf "%.1f", s+0}')
    echo "$(date +%s) $N $((RKB/1024)) ${CPU}" >> "$OUT"
    PL=$(echo "$TREE" | tr '\n' ',' | sed 's/,$//')
    lsof -i -nP -a -p "$PL" 2>/dev/null | awk 'NR>1 && ($8=="TCP"||$8=="UDP") {print $9}' \
      | grep -vE '127\.0\.0\.1|\[::1\]|localhost|\*:' | sed 's/.*->//' | sed 's/:[0-9]*$//' \
      | grep -vE '^$' | sort -u >> "$REM"
  else echo "$(date +%s) 0 0 0.0" >> "$OUT"; fi
  sleep 5
done

{ echo; echo "== unique remote peers (ip; reverse-dns best effort) =="
  sort -u "$REM" | while read ip; do
    [ -z "$ip" ] && continue
    h=$(dig +short -x "$ip" 2>/dev/null | head -1); [ -z "$h" ] && h="(no ptr)"
    echo "$ip  $h"
  done
  echo; echo "== summary =="
  awk '/^[0-9]+ / {n++; rss+=$3; cpu+=$4; if($3>mr)mr=$3; if($4>mc)mc=$4} END{if(n>0)printf "samples:%d avg_procs:%.0f avg_rss_mb:%.0f max_rss_mb:%d avg_cpu:%.1f max_cpu:%.1f\n",n,0,rss/n,mr,cpu/n,mc}' "$OUT"
  awk '/^[0-9]+ / {n++; p+=$2} END{if(n>0)printf "avg_procs:%.1f\n",p/n}' "$OUT"
  echo "finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"; } >> "$OUT"
rm -f "$REM"; echo "$OUT"
