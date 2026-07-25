#!/usr/bin/env bun

import { LOG_DIR, parseArgs } from "./lib/utils.ts";
import { setup, teardown } from "./setup.ts";
import { testRecord } from "./tests/record.ts";

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));

  const ctx = await setup(args);
  let passed = false;
  try {
    await testRecord(ctx);
    passed = true;
    console.log("npm e2e tests passed");
    console.log(`logs: ${LOG_DIR}`);
  } finally {
    await teardown(ctx, passed, Boolean(args.keep));
  }
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
