#!/usr/bin/env python3
"""Calls every MCP tool against the real archive and fails if any of them errors.

A wrong column name inside a SQL string literal compiles cleanly. It only fails
when an agent calls the tool, which is how meeting_transcript shipped querying
three columns that do not exist. This is the cheapest thing that catches it.

    python3 scripts/check-mcp-tools.py [path-to-litepipe-mcp]

Defaults to .build/debug/litepipe-mcp. Reads LITEPIPE_DB like the binary does.
"""

import json
import subprocess
import sys
from pathlib import Path

BIN = Path(sys.argv[1] if len(sys.argv) > 1 else ".build/debug/litepipe-mcp")


class Bridge:
    """One process, one request at a time, which is all the protocol needs here."""

    def __init__(self, binary):
        self.proc = subprocess.Popen(
            [str(binary)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        self.next_id = 0
        self.send("initialize", {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
        })

    def send(self, method, params):
        self.next_id += 1
        request = {"jsonrpc": "2.0", "id": self.next_id, "method": method,
                   "params": params}
        self.proc.stdin.write(json.dumps(request) + "\n")
        self.proc.stdin.flush()
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise SystemExit("the bridge closed stdout, so it died")
            reply = json.loads(line)
            if reply.get("id") == self.next_id:
                return reply

    def call(self, name, arguments):
        return self.send("tools/call", {"name": name, "arguments": arguments})

    def close(self):
        self.proc.stdin.close()
        self.proc.wait(timeout=10)


def text_of(reply):
    content = reply.get("result", {}).get("content", [])
    return "\n".join(part.get("text", "") for part in content)


def one_value(bridge, sql):
    """First cell of a query, or None. Used to find ids that actually exist."""
    reply = bridge.call("query", {"sql": sql})
    if "error" in reply:
        return None
    lines = [line for line in text_of(reply).splitlines() if line.strip()]
    return lines[1].split("\t")[0] if len(lines) > 1 else None


def main():
    if not BIN.is_file():
        raise SystemExit(f"{BIN} is not there. Run swift build first.")

    bridge = Bridge(BIN)

    declared = {t["name"] for t in bridge.send("tools/list", {})["result"]["tools"]}
    print(f"{len(declared)} tools declared: {', '.join(sorted(declared))}\n")

    meeting_id = one_value(bridge, "SELECT id FROM meetings ORDER BY meeting_start DESC LIMIT 1")
    # The wordiest screen in the archive, not the newest one. A result longer than
    # the character cap takes a different path out of the reader, and that path
    # used to hand back a row with one column, which crashed every caller that
    # reads a fixed one. Picking the largest exercises it on purpose.
    frame_id = one_value(bridge, """
        SELECT id FROM frames
        ORDER BY length(COALESCE(NULLIF(full_text,''), accessibility_text, '')) DESC LIMIT 1
        """)

    checks = [
        ("search_content", {"query": "the", "limit": 3}),
        # Enough hits to run past the cap.
        ("search_content", {"query": "the", "limit": 100}),
        ("activity_summary", {}),
        ("list_meetings", {"limit": 3}),
        ("query", {"sql": "SELECT count(*) FROM frames"}),
        ("query", {"sql": "SELECT id, full_text FROM frames ORDER BY id DESC LIMIT 200"}),
    ]
    if meeting_id:
        checks.append(("meeting_transcript", {"meeting_id": int(meeting_id)}))
    else:
        print("no meetings in this archive, skipping meeting_transcript")
    if frame_id:
        checks.append(("frame_context", {"frame_id": int(frame_id)}))
    else:
        print("no frames in this archive, skipping frame_context")

    failed = []
    for name, arguments in checks:
        if name not in declared:
            failed.append((name, "not declared by the server"))
            continue
        reply = bridge.call(name, arguments)
        if "error" in reply:
            failed.append((name, reply["error"].get("message", "unknown error")))
            print(f"FAIL  {name}: {failed[-1][1]}")
            continue
        if reply.get("result", {}).get("isError"):
            failed.append((name, text_of(reply)[:120]))
            print(f"FAIL  {name}: {failed[-1][1]}")
            continue
        first = text_of(reply).splitlines()
        print(f"ok    {name}: {first[0][:80] if first else '(empty)'}")

    untested = declared - {name for name, _ in checks}
    if untested:
        print(f"\nnot called: {', '.join(sorted(untested))}")

    bridge.close()

    if failed:
        print(f"\n{len(failed)} of {len(checks)} tools failed")
        return 1
    print(f"\nall {len(checks)} calls answered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
