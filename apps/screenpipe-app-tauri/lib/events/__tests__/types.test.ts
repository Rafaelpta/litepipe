import { describe, it, expect } from "bun:test";
import { pipeSessionId, parsePipeSessionId, AGENT_TOPICS } from "../types";

describe("pipeSessionId", () => {
  it("formats pipe sessions with a stable prefix", () => {
    expect(pipeSessionId("apple-photo-sync", 42)).toBe("pipe:apple-photo-sync:42");
  });

  it("accepts string execution ids", () => {
    expect(pipeSessionId("foo", "7")).toBe("pipe:foo:7");
  });

  it("round-trips through parsePipeSessionId", () => {
    const sid = pipeSessionId("my-pipe", 1234);
    expect(parsePipeSessionId(sid)).toEqual({ pipeName: "my-pipe", executionId: 1234 });
  });

  it("handles pipe names that contain colons", () => {
    const sid = pipeSessionId("scope:thing", 9);
    // Last colon delimits the execution id — pipe name keeps any inner colons.
    expect(parsePipeSessionId(sid)).toEqual({ pipeName: "scope:thing", executionId: 9 });
  });
});

describe("parsePipeSessionId", () => {
  it("returns null for non-pipe ids", () => {
    expect(parsePipeSessionId("a3f2c0e1-1111-2222-3333-444455556666")).toBeNull();
    expect(parsePipeSessionId("chat-123")).toBeNull();
    expect(parsePipeSessionId("")).toBeNull();
  });

  it("returns null when the execution id isn't numeric", () => {
    expect(parsePipeSessionId("pipe:foo:not-a-number")).toBeNull();
  });

  it("returns null when the pipe name is empty", () => {
    expect(parsePipeSessionId("pipe::42")).toBeNull();
  });
});

describe("AGENT_TOPICS", () => {
  it("exposes the expected topic names", () => {
    expect(AGENT_TOPICS.event).toBe("agent_event");
    expect(AGENT_TOPICS.terminated).toBe("agent_terminated");
    expect(AGENT_TOPICS.evicted).toBe("agent_session_evicted");
  });
});
