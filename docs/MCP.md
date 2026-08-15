# Connecting an agent over MCP

litepipe ships a bridge that lets any MCP client read the archive. It is a second
executable inside the app:

```
/Applications/litepipe.app/Contents/MacOS/litepipe-mcp
```

There is nothing to install. No Node, no Python, no npm package, no port, no API
key. The client spawns the binary and talks to it over stdin and stdout, and the
binary opens `~/.litepipe/db.sqlite` directly. It answers while litepipe itself is
closed.

It is read only. It never writes to the archive, never opens a socket, and never
sends anything anywhere. Those are not promises in a README: every tool declares
`readOnlyHint: true` and `openWorldHint: false` in its MCP annotations, so a client
can check for itself.

## Connect

### Claude Code

```
claude mcp add --scope user litepipe -- /Applications/litepipe.app/Contents/MacOS/litepipe-mcp
```

Without `--scope user` the server is registered for the current directory only, and
every session started anywhere else answers as though the archive does not exist.
A memory is not a per project tool.

### Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "litepipe": {
      "command": "/Applications/litepipe.app/Contents/MacOS/litepipe-mcp",
      "args": []
    }
  }
}
```

### Cursor

The same entry, in `~/.cursor/mcp.json`.

### Or use the app

Open litepipe, go to Connect, and pick the client. It writes the same entry and
leaves any other servers in the file alone.

> **Move the app to Applications first.** If you run litepipe straight from the
> mounted disk image, the path written into the config points at `/Volumes/...`,
> which stops existing the moment you eject. Connect refuses in that case rather
> than leaving you with a server that fails every question.

Point any of these at a different archive with `LITEPIPE_DB=/path/to/db.sqlite`.

## The six tools

Every answer is capped at about 12,000 characters, so a broad question comes back
clipped rather than burying the answer in evidence and spending your context
window on it.

### `search_content`

Full text search over everything captured on screen, newest first, with the
sentence that matched and where it came from.

| argument | |
|---|---|
| `query` | required. Each word also matches longer words starting with it |
| `limit` | default 25, maximum 100 |
| `since` | ISO date or datetime, inclusive |
| `until` | ISO date or datetime, exclusive |

Returns the timestamp, app, window and URL of each moment, the matching sentence,
and a `frame` id you can hand to `frame_context`.

### `activity_summary`

Where a day went: which apps, how many captures each, first and last activity, and
any meetings. Start here for "what did I do" before pulling any text.

| argument | |
|---|---|
| `date` | `YYYY-MM-DD`. Defaults to the most recent day with captures |

### `list_meetings`

Meetings detected from audio, newest first, with how many transcript segments each
one has.

| argument | |
|---|---|
| `limit` | default 20, maximum 100 |

### `meeting_transcript`

One meeting read in order, with speakers and times.

| argument | |
|---|---|
| `meeting_id` | required. From `list_meetings` |

### `frame_context`

A search hit is a sentence with no surroundings. This gives you the rest of that
screen, plus the captures immediately before and after it.

| argument | |
|---|---|
| `frame_id` | required. From `search_content` |
| `neighbours` | how many captures either side. Default 2, maximum 10 |

### `query`

Read only SQL, for anything the five fixed tools do not cover. "Which terminal
windows came back most often this week, grouped by project" is not a search, and
pretending it is produces a worse answer than letting the model write the query.

| argument | |
|---|---|
| `sql` | required. A single `SELECT` or `WITH` statement |

`LIMIT 100` is added if you leave one out. Anything that writes is refused, and the
connection is opened read only underneath that, so the refusal is a second lock on
a door that is already locked.

Timestamps are UTC in ISO 8601. Compare them with `datetime(timestamp)` and group
with `date(timestamp)`.

**`frames`** is one row per captured moment.

```
frames(id, timestamp, app_name, window_name, browser_url, full_text,
       accessibility_text, capture_trigger, text_source, document_path,
       video_chunk_id, offset_index)
```

**`elements`** is every piece of text on that screen as its own row, with where it
sat. The bounds run 0 to 1, and `top_bound` 0 is the top of the screen.

```
elements(id, frame_id, source, role, text, parent_id, depth,
         left_bound, top_bound, width_bound, height_bound,
         confidence, sort_order, properties, on_screen)
```

This is the table that lets you read a layout instead of a page of text, and it is
worth understanding because some of the most useful questions are only answerable
through it. Rows with close `top_bound` values were close together on screen, so
joining `elements` to itself on a small difference within one frame gives you "the
line underneath this one". That is how you read the message under a name in a chat
sidebar, or the value under a label in a form.

A worked example. WhatsApp Web exposes only its conversation list to the
accessibility layer, never the open thread, so searching for the text of a message
finds nothing. But every capture holds one line of the last message per
conversation, and captures happen all day. Joining on position and ordering by time
reconstructs the thread from hundreds of glances at the list:

```sql
WITH k AS (SELECT frame_id, top_bound FROM elements WHERE text = 'Ana')
SELECT min(f.timestamp), e.text
FROM elements e
JOIN k ON k.frame_id = e.frame_id
JOIN frames f ON f.id = e.frame_id
WHERE e.top_bound > k.top_bound AND e.top_bound < k.top_bound + 0.05
  AND length(e.text) > 12 AND e.text <> 'Ana'
GROUP BY e.text ORDER BY 1
```

**The rest.**

```
audio_transcriptions(id, audio_chunk_id, timestamp, transcription, device,
                     is_input_device, speaker_id, transcription_engine,
                     start_time, end_time)     -- speaker_id joins speakers(id, name)
ui_events(id, timestamp, event_type, text_content, app_name, window_title,
          browser_url, element_role, element_name, frame_id)
                                               -- typed, clicked, copied
ocr_text(frame_id, text)
meetings(id, meeting_start, meeting_end, meeting_app)
meeting_transcript_segments(meeting_id, timestamp, speaker, transcription)
video_chunks(id, file_path, fps)
```

## Try it without a client

The bridge is a plain stdio program, so you can drive it by hand. Two lines of
JSON RPC, one per line:

```bash
printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | /Applications/litepipe.app/Contents/MacOS/litepipe-mcp
```

Diagnostics go to stderr, so stdout carries protocol messages and nothing else.

## What it will not do

It will not write to the archive, tag anything, rename a speaker, start or stop
recording, or delete a moment. Those are the app's job, behind a window where a
person can see what is happening.

It will not reach the network. There is no cloud endpoint, no telemetry and no
account, so there is nothing to configure and nothing to opt out of.

It will not read anything but the archive. If a moment was never captured, because
capture was paused or the window was on the ignore list, it does not exist here.

## Protocol

Server name `litepipe`. Speaks MCP `2025-06-18`, `2025-03-26` and `2024-11-05`,
and answers a client asking for anything else with the newest one it does speak.
Tools only: no resources, no prompts, no sampling.
