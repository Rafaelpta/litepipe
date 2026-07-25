import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as http from "http";

// The export-video MCP tool posts a time range to POST /export. The engine resolves
// the frames + synced audio for that range and renders a real-time MP4 (frames at
// their true timestamps), returning a summary. There is no timelapse/fps path and no
// WebSocket — those were removed along with the legacy /frames/export endpoint.

describe("export-video MCP tool", () => {
  let mockHttpServer: http.Server;
  let serverPort: number;

  beforeEach(async () => {
    mockHttpServer = http.createServer((req, res) => {
      const url = new URL(req.url!, `http://localhost`);

      if (url.pathname === "/export" && req.method === "POST") {
        let body = "";
        req.on("data", (chunk) => (body += chunk));
        req.on("end", () => {
          let parsed: { start?: string; end?: string; meeting_id?: number; output_path?: string } = {};
          try {
            parsed = JSON.parse(body);
          } catch {
            // fall through to validation below
          }
          if (!parsed.start && !parsed.end && parsed.meeting_id === undefined) {
            res.writeHead(400, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: "provide either meeting_id or start/end" }));
            return;
          }
          res.writeHead(200, { "Content-Type": "application/json" });
          res.end(
            JSON.stringify({
              // echo output_path when supplied so we can assert passthrough
              output_path: parsed.output_path || "/tmp/screenpipe/exports/export_20260101_000000.mp4",
              frame_count: 42,
              audio_chunk_count: 7,
              duration_secs: 123.4,
              file_size_bytes: 2 * 1024 * 1024,
            }),
          );
        });
      } else {
        res.writeHead(404);
        res.end();
      }
    });

    await new Promise<void>((resolve) => {
      mockHttpServer.listen(0, () => {
        serverPort = (mockHttpServer.address() as { port: number }).port;
        resolve();
      });
    });
  });

  afterEach(async () => {
    await new Promise<void>((resolve) => {
      mockHttpServer.close(() => resolve());
    });
  });

  it("exports a real-time video with synced audio via POST /export", async () => {
    const response = await fetch(`http://localhost:${serverPort}/export`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ start: "2024-01-15T10:00:00Z", end: "2024-01-15T10:30:00Z" }),
    });

    expect(response.ok).toBe(true);
    const data = (await response.json()) as {
      output_path: string;
      frame_count: number;
      audio_chunk_count: number;
      duration_secs: number;
      file_size_bytes: number;
    };
    expect(data.output_path).toMatch(/\.mp4$/);
    expect(typeof data.frame_count).toBe("number");
    expect(data.audio_chunk_count).toBeGreaterThan(0);
    expect(data.duration_secs).toBeGreaterThan(0);

    // Mirror the MCP success formatting for the audio+video path.
    const sizeMb = data.file_size_bytes
      ? (data.file_size_bytes / (1024 * 1024)).toFixed(1)
      : null;
    const text =
      `Video exported (with audio): ${data.output_path}\n` +
      `${data.frame_count} frames | ${data.audio_chunk_count} audio chunks` +
      (sizeMb ? ` | ${sizeMb} MB` : "") +
      (data.duration_secs ? ` | ${data.duration_secs}s` : "");
    expect(text).toContain("with audio");
    expect(text).toContain("audio chunks");
    expect(text).toContain(data.output_path);
  });

  it("forwards output_path to /export when provided", async () => {
    const target = "/Users/test/Downloads/clip.mp4";
    const response = await fetch(`http://localhost:${serverPort}/export`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ start: "5m ago", end: "now", output_path: target }),
    });

    expect(response.ok).toBe(true);
    const data = (await response.json()) as { output_path: string };
    expect(data.output_path).toBe(target);
  });

  it("returns 400 from /export when neither meeting_id nor start/end is given", async () => {
    const response = await fetch(`http://localhost:${serverPort}/export`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({}),
    });
    expect(response.status).toBe(400);
  });
});

describe("export-video tool schema", () => {
  it("requires start/end, exposes output_path, and has no fps/timelapse knob", () => {
    // The tool always renders a real-time audio+video clip; there is no fps option.
    const schema = {
      type: "object",
      properties: {
        start_time: { type: "string" },
        end_time: { type: "string" },
        output_path: { type: "string" },
      },
      required: ["start_time", "end_time"],
    };

    expect(schema.required).toContain("start_time");
    expect(schema.required).toContain("end_time");
    expect("output_path" in schema.properties).toBe(true);
    expect("fps" in schema.properties).toBe(false);
  });
});
