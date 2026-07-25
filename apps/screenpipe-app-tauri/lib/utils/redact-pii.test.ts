import { describe, it, expect } from "bun:test";
import { redactPii } from "./redact-pii";

describe("redactPii", () => {
  // ====== Phone numbers — should redact ======

  it("redacts US phone with dashes", () => {
    expect(redactPii("Call me at 234-567-8901")).toBe(
      "Call me at [PHONE]"
    );
  });

  it("redacts US phone with parenthesized area code", () => {
    expect(redactPii("Phone: (555) 123-4567")).toBe("Phone: [PHONE]");
  });

  it("redacts US phone with dots", () => {
    expect(redactPii("Cell: 234.567.8901")).toBe("Cell: [PHONE]");
  });

  it("redacts international phone with country code", () => {
    expect(redactPii("Reach me at +1-234-567-8901")).toBe(
      "Reach me at [PHONE]"
    );
  });

  it("redacts compact international phone", () => {
    expect(redactPii("+12345678901")).toBe("[PHONE]");
  });

  // ====== Accessibility bounds — must NOT redact ======
  // Bug: old regex mangled bounding box coordinates as phone numbers
  // e.g. "left": 47692 became "left": [PHONE]7692

  it("does not redact accessibility bounding box JSON", () => {
    const bounds = `{"left": 47692, "top": 111658, "width": 44767, "height": 39496}`;
    expect(redactPii(bounds)).toBe(bounds);
  });

  it("does not redact structured accessibility bounds", () => {
    const text = `"left_bound": 47692, "top_bound": 111658, "width_bound": 44767`;
    expect(redactPii(text)).toBe(text);
  });

  it("does not redact individual coordinate values", () => {
    expect(redactPii("47692")).toBe("47692");
    expect(redactPii("111658")).toBe("111658");
    expect(redactPii("44767")).toBe("44767");
    expect(redactPii("39496")).toBe("39496");
    expect(redactPii("62796")).toBe("62796");
    expect(redactPii("16272")).toBe("16272");
  });

  it("does not redact full Pi accessibility tree output", () => {
    const piOutput = `{
  "role": "Button",
  "text": "Leave",
  "depth": 17,
  "bounds": {
    "left": 47692,
    "top": 111658,
    "width": 44767,
    "height": 39496
  }
}`;
    expect(redactPii(piOutput)).toBe(piOutput);
  });

  // ====== Numeric IDs and hashes — must NOT redact ======

  it("does not redact frame IDs", () => {
    expect(redactPii("frame_id: 549130407")).toBe("frame_id: 549130407");
  });

  it("does not redact monitor IDs", () => {
    expect(redactPii("monitor 605818409")).toBe("monitor 605818409");
  });

  it("does not redact hash values", () => {
    expect(redactPii("hash=5542957767813040527")).toBe(
      "hash=5542957767813040527"
    );
  });

  it("does not redact process IDs", () => {
    expect(redactPii("pid: 25616")).toBe("pid: 25616");
  });

  it("does not redact meeting IDs", () => {
    expect(redactPii("meeting started (id=68)")).toBe(
      "meeting started (id=68)"
    );
  });

  it("does not redact bare 10-digit numbers", () => {
    // Bare digits without formatting are likely IDs, not phones
    expect(redactPii("2345678901")).toBe("2345678901");
  });

  it("does not redact pixel dimensions", () => {
    expect(redactPii("2880x1800")).toBe("2880x1800");
    expect(redactPii("1920x1080")).toBe("1920x1080");
  });

  it("does not redact elapsed time and row counts", () => {
    expect(redactPii("elapsed=100.4287155s")).toBe("elapsed=100.4287155s");
    expect(redactPii("rows_returned=1434")).toBe("rows_returned=1434");
  });

  // ====== Other PII types ======

  it("redacts email addresses", () => {
    expect(redactPii("contact user@example.com")).toBe(
      "contact [EMAIL]"
    );
  });

  it("redacts SSN", () => {
    expect(redactPii("SSN: 123-45-6789")).toBe("SSN: [SSN]");
  });

  it("redacts credit card numbers", () => {
    expect(redactPii("card: 4532-1234-5678-9012")).toBe("card: [CARD]");
  });

  it("redacts bearer tokens", () => {
    expect(
      redactPii("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.sig")
    ).toBe("Bearer [REDACTED]");
  });

  it("redacts API keys", () => {
    expect(redactPii("api_key=sk_live_abc123defghijklmnop")).toContain(
      "[REDACTED]"
    );
  });

  // ====== Path redaction ======

  it("redacts Unix home paths", () => {
    expect(redactPii("/Users/louisbeaumont/.screenpipe")).toBe(
      "/Users/[USER]/.screenpipe"
    );
  });

  it("redacts Windows home paths", () => {
    expect(redactPii("C:\\Users\\DavidBattaglia\\.screenpipe")).toBe(
      "C:\\Users\\[USER]\\.screenpipe"
    );
  });

  it("redacts Linux home paths", () => {
    expect(redactPii("/home/david/.config")).toBe("/home/[USER]/.config");
  });

  // ====== Mixed content (real log lines) ======

  it("handles real log line with coordinates without mangling", () => {
    const log = `snapshot compaction: 59 frames, 22.2MB to 8.9MB (2.5x), 59 JPEGs deleted`;
    expect(redactPii(log)).toBe(log);
  });

  it("handles real accessibility Pi output with user path", () => {
    const input = `Pi config merged at "C:\\Users\\DavidBattaglia\\.pi\\agent\\models.json"`;
    expect(redactPii(input)).toBe(
      `Pi config merged at "C:\\Users\\[USER]\\.pi\\agent\\models.json"`
    );
  });
});
