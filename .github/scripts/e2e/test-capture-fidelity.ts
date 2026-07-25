import {
  suite, test, summary, screenshot, bb, fetchJson, sleep,
  ARTIFACTS_DIR, HEALTH_URL, SEARCH_URL,
} from "./lib";
import { join } from "path";

const runId = Date.now().toString(36);

// Ground truth tracking
interface GroundTruth {
  startTime: string;
  endTime: string;
  markers: {
    alpha: string;
    beta: string;
    verify: string;
  };
  expected: {
    textEvents: number;
    appSwitches: number;
    clipboardEvents: number;
  };
}

const groundTruth: GroundTruth = {
  startTime: new Date().toISOString(),
  endTime: "",
  markers: {
    alpha: `FIDELITY_MARKER_ALPHA_${runId}`,
    beta: `FIDELITY_MARKER_BETA_${runId}`,
    verify: `screenpipe-e2e-verify-${runId}`,
  },
  expected: {
    textEvents: 0,
    appSwitches: 0,
    clipboardEvents: 0,
  },
};

suite("capture-fidelity");

// Helper to build search URL with time window
function searchUrl(params: Record<string, string | number>): string {
  const p = new URLSearchParams();
  p.set("start_time", groundTruth.startTime);
  if (groundTruth.endTime) {
    p.set("end_time", groundTruth.endTime);
  }
  for (const [k, v] of Object.entries(params)) {
    p.set(k, String(v));
  }
  return `${SEARCH_URL}?${p.toString()}`;
}

// ── Phase 1: TextEdit — typing + clipboard (30s) ────────────────────────

console.log("\n  Phase 1: TextEdit — typing + clipboard");

Bun.spawnSync(["osascript", "-e", 'tell application "TextEdit" to activate']);
await sleep(3000);
groundTruth.expected.appSwitches++;

// Type marker strings
await bb("type", groundTruth.markers.alpha);
await sleep(1000);
await bb("press", "Return");
await sleep(500);
await bb("type", groundTruth.markers.verify);
await sleep(1000);
groundTruth.expected.textEvents += 2;

// Select all + copy (clipboard event)
await bb("shortcut", "a", "--modifiers", "cmd");
await sleep(500);
await bb("shortcut", "c", "--modifiers", "cmd");
await sleep(1000);
groundTruth.expected.clipboardEvents++;

await screenshot("phase1-textedit");
await sleep(2000);

// ── Phase 2: Terminal — app switch + commands (30s) ──────────────────────

console.log("  Phase 2: Terminal — app switch + commands");

Bun.spawnSync(["osascript", "-e", 'tell application "Terminal" to activate']);
await sleep(3000);
groundTruth.expected.appSwitches++;

await bb("type", `echo ${groundTruth.markers.beta}`);
await sleep(500);
await bb("press", "Return");
await sleep(1000);
groundTruth.expected.textEvents++;

await screenshot("phase2-terminal");
await sleep(2000);

// ── Phase 3: Finder — window management (30s) ───────────────────────────

console.log("  Phase 3: Finder — window management");

Bun.spawnSync(["osascript", "-e", 'tell application "Finder" to activate']);
await sleep(3000);
groundTruth.expected.appSwitches++;

// New Finder window, then close
await bb("shortcut", "n", "--modifiers", "cmd");
await sleep(2000);
await bb("shortcut", "w", "--modifiers", "cmd");
await sleep(2000);

await screenshot("phase3-finder");

// ── Phase 4: Rapid app switching — stress test (45s) ────────────────────

console.log("  Phase 4: Rapid app switching — stress test");

for (let i = 0; i < 4; i++) {
  Bun.spawnSync(["osascript", "-e", 'tell application "TextEdit" to activate']);
  await sleep(1500);
  groundTruth.expected.appSwitches++;

  Bun.spawnSync(["osascript", "-e", 'tell application "Terminal" to activate']);
  await sleep(1500);
  groundTruth.expected.appSwitches++;

  Bun.spawnSync(["osascript", "-e", 'tell application "Finder" to activate']);
  await sleep(1500);
  groundTruth.expected.appSwitches++;
}

await screenshot("phase4-rapid-switch");

// ── Settling period ─────────────────────────────────────────────────────

console.log("  Settling period (90s) — waiting for pipeline flush...");
await sleep(90_000);

groundTruth.endTime = new Date().toISOString();

// ── Assertions ──────────────────────────────────────────────────────────

console.log("\n  Running assertions...\n");

// 1. Pipeline healthy
await test("pipeline healthy post-scenario", async () => {
  const health = await fetchJson(HEALTH_URL);
  if (health.status === "degraded") {
    throw new Error(`pipeline degraded: ${JSON.stringify(health)}`);
  }
});

// 2. Frame drop rate < 20%
await test("frame drop rate < 20%", async () => {
  const health = await fetchJson(HEALTH_URL);
  const dropRate = health?.pipeline?.frame_drop_rate ?? health?.frame_drop_rate ?? 0;
  if (dropRate > 0.2) {
    throw new Error(`frame drop rate too high: ${(dropRate * 100).toFixed(1)}%`);
  }
  console.log(`  frame drop rate: ${(dropRate * 100).toFixed(1)}%`);
});

// 3. Frames captured > 0
await test("frames captured > 0", async () => {
  const health = await fetchJson(HEALTH_URL);
  const frames = health?.pipeline?.frames_captured ?? health?.frames_captured ?? 0;
  if (frames <= 0) {
    if (health.frame_status !== "ok") {
      throw new Error(`no frames captured, frame_status: ${health.frame_status}`);
    }
  }
  console.log(`  frames/frame_status: ${frames || health.frame_status}`);
});

// 4. OCR marker ALPHA found
await test("OCR marker ALPHA found", async () => {
  const url = searchUrl({ content_type: "ocr", q: groundTruth.markers.alpha, limit: 5 });
  const data = await fetchJson(url);
  const count = data?.data?.length ?? 0;
  if (count < 1) {
    throw new Error(`marker ALPHA not found in OCR: ${groundTruth.markers.alpha}`);
  }
  console.log(`  found ${count} OCR result(s) with ALPHA marker`);
});

// 5. OCR marker BETA found
await test("OCR marker BETA found", async () => {
  const url = searchUrl({ content_type: "ocr", q: groundTruth.markers.beta, limit: 5 });
  const data = await fetchJson(url);
  const count = data?.data?.length ?? 0;
  if (count < 1) {
    throw new Error(`marker BETA not found in OCR: ${groundTruth.markers.beta}`);
  }
  console.log(`  found ${count} OCR result(s) with BETA marker`);
});

// 6. OCR verification text found
await test("OCR verification text found", async () => {
  const url = searchUrl({ content_type: "ocr", q: groundTruth.markers.verify, limit: 5 });
  const data = await fetchJson(url);
  const count = data?.data?.length ?? 0;
  if (count < 1) {
    throw new Error(`verification text not found: ${groundTruth.markers.verify}`);
  }
  console.log(`  found ${count} OCR result(s) with verification text`);
});

// 7. Text input events detected
await test("text input events detected", async () => {
  const url = searchUrl({ content_type: "input", limit: 50 });
  const data = await fetchJson(url);
  const results = data?.data ?? [];
  const textEvents = results.filter((r: any) =>
    r?.content?.event_type === "text" || r?.content?.type === "text"
  );
  if (textEvents.length < 1) {
    throw new Error(`no text input events (total input events: ${results.length})`);
  }
  console.log(`  text input events: ${textEvents.length}`);
});

// 8. App switch events >= 50% of expected
await test("app switch events >= 50% expected", async () => {
  const url = searchUrl({ content_type: "input", limit: 100 });
  const data = await fetchJson(url);
  const results = data?.data ?? [];
  const switches = results.filter((r: any) =>
    r?.content?.event_type === "app_switch" || r?.content?.type === "app_switch"
  );
  const expected = groundTruth.expected.appSwitches;
  const threshold = Math.floor(expected * 0.5);
  if (switches.length < threshold) {
    throw new Error(`app switches: ${switches.length} < ${threshold} (50% of ${expected})`);
  }
  console.log(`  app switches: ${switches.length} / ${expected} expected`);
});

// 9. Click/keyboard events exist
await test("click/keyboard events exist", async () => {
  const url = searchUrl({ content_type: "input", limit: 50 });
  const data = await fetchJson(url);
  const count = data?.data?.length ?? 0;
  if (count < 1) {
    throw new Error("no input events at all");
  }
  console.log(`  total input events: ${count}`);
});

// 10. Clipboard event detected
await test("clipboard event detected", async () => {
  const url = searchUrl({ content_type: "input", limit: 100 });
  const data = await fetchJson(url);
  const results = data?.data ?? [];
  const clipboard = results.filter((r: any) =>
    r?.content?.event_type === "clipboard" || r?.content?.type === "clipboard"
  );
  if (clipboard.length < 1) {
    throw new Error(`no clipboard events (total input events: ${results.length})`);
  }
  console.log(`  clipboard events: ${clipboard.length}`);
});

// 11. TextEdit in OCR results
await test("TextEdit in OCR results", async () => {
  const url = searchUrl({ content_type: "ocr", app_name: "TextEdit", limit: 5 });
  const data = await fetchJson(url);
  const count = data?.data?.length ?? 0;
  if (count < 1) {
    throw new Error("no OCR results from TextEdit");
  }
  console.log(`  TextEdit OCR results: ${count}`);
});

// 12. Terminal in OCR results
await test("Terminal in OCR results", async () => {
  const url = searchUrl({ content_type: "ocr", app_name: "Terminal", limit: 5 });
  const data = await fetchJson(url);
  const count = data?.data?.length ?? 0;
  if (count < 1) {
    throw new Error("no OCR results from Terminal");
  }
  console.log(`  Terminal OCR results: ${count}`);
});

// 13. Accessibility data captured
await test("accessibility data captured", async () => {
  try {
    const url = searchUrl({ content_type: "accessibility", limit: 5 });
    const data = await fetchJson(url);
    const count = data?.data?.length ?? 0;
    if (count < 1) {
      throw new Error("no accessibility data captured");
    }
    console.log(`  accessibility results: ${count}`);
  } catch (err: any) {
    if (err.message.includes("HTTP")) {
      // Fallback: try ui content type
      const url = searchUrl({ content_type: "ui", limit: 5 });
      const data = await fetchJson(url);
      const count = data?.data?.length ?? 0;
      if (count < 1) {
        throw new Error("no accessibility/UI data captured");
      }
      console.log(`  UI/accessibility results: ${count}`);
    } else {
      throw err;
    }
  }
});

// 14. CPU usage < 150%
await test("CPU usage < 150%", async () => {
  const proc = Bun.spawnSync([
    "bash", "-c",
    "ps aux | grep screenpipe | grep -v grep | awk '{sum += $3} END {print sum}'",
  ]);
  const cpu = parseFloat(proc.stdout.toString().trim()) || 0;
  if (cpu > 150) {
    throw new Error(`CPU too high: ${cpu.toFixed(1)}%`);
  }
  console.log(`  screenpipe CPU: ${cpu.toFixed(1)}%`);
});

// 15. Memory < 2GB
await test("memory < 2GB", async () => {
  const proc = Bun.spawnSync([
    "bash", "-c",
    "ps aux | grep screenpipe | grep -v grep | awk '{sum += $6} END {print sum}'",
  ]);
  const rssKB = parseFloat(proc.stdout.toString().trim()) || 0;
  const rssMB = rssKB / 1024;
  if (rssMB > 2048) {
    throw new Error(`memory too high: ${rssMB.toFixed(0)} MB`);
  }
  console.log(`  screenpipe memory: ${rssMB.toFixed(0)} MB`);
});

// 16. Generate fidelity report
await test("generate fidelity report", async () => {
  const report = {
    runId,
    groundTruth,
    timestamp: new Date().toISOString(),
    system: {
      hostname: Bun.spawnSync(["hostname"]).stdout.toString().trim(),
      os: Bun.spawnSync(["sw_vers", "-productVersion"]).stdout.toString().trim(),
    },
  };
  const reportPath = join(ARTIFACTS_DIR, "capture-fidelity-report.json");
  await Bun.write(reportPath, JSON.stringify(report, null, 2));
  console.log(`  report written to ${reportPath}`);
});

// ── Cleanup ─────────────────────────────────────────────────────────────

Bun.spawnSync(["osascript", "-e", 'tell application "TextEdit" to quit saving no']);
Bun.spawnSync(["osascript", "-e", 'tell application "Terminal" to quit']);

const ok = summary();
process.exit(ok ? 0 : 1);
