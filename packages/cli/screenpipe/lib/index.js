const { execFileSync, execSync } = require("child_process");
const { join, dirname } = require("path");
const { existsSync, chmodSync } = require("fs");

const PLATFORMS = {
  "darwin-arm64": "@screenpipe/cli-darwin-arm64",
  "darwin-x64": "@screenpipe/cli-darwin-x64",
  "linux-x64": "@screenpipe/cli-linux-x64",
  "win32-x64": "@screenpipe/cli-win32-x64",
};

/**
 * Resolve the path to the screenpipe native binary for the current platform.
 * Returns the absolute path, or null if not installed.
 */
function getBinaryPath() {
  const key = `${process.platform}-${process.arch}`;
  const pkg = PLATFORMS[key];
  if (!pkg) return null;

  try {
    const pkgPath = require.resolve(`${pkg}/package.json`);
    const ext = process.platform === "win32" ? ".exe" : "";
    const binPath = join(dirname(pkgPath), "bin", `screenpipe${ext}`);
    if (!existsSync(binPath)) return null;

    // Ensure executable
    if (process.platform !== "win32") {
      try { chmodSync(binPath, 0o755); } catch {}
    }
    if (process.platform === "darwin") {
      try { execSync(`xattr -d com.apple.quarantine "${binPath}" 2>/dev/null || true`); } catch {}
    }

    return binPath;
  } catch {
    return null;
  }
}

/**
 * Get the local API authentication key.
 * Runs `screenpipe auth token` using the bundled native binary.
 * No PATH dependency — uses the resolved binary directly.
 * Returns the API key string, or empty string if not available.
 */
function getApiKey() {
  const bin = getBinaryPath();
  if (!bin) return "";

  try {
    return execFileSync(bin, ["auth", "token"], {
      timeout: 10000,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch {
    return "";
  }
}

module.exports = { getBinaryPath, getApiKey };
