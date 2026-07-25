import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync, mkdirSync } from 'node:fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SCREENSHOT_DIR = resolve(__dirname, '../screenshots');

export function ensureScreenshotDir(): void {
  if (!existsSync(SCREENSHOT_DIR)) {
    mkdirSync(SCREENSHOT_DIR, { recursive: true });
  }
}

export async function saveScreenshot(name: string): Promise<string> {
  ensureScreenshotDir();
  const filepath = resolve(SCREENSHOT_DIR, `${name}.png`);
  await browser.saveScreenshot(filepath);
  console.log(`Screenshot saved: ${filepath}`);
  return filepath;
}

export function getScreenshotPath(name: string): string {
  return resolve(SCREENSHOT_DIR, `${name}.png`);
}
