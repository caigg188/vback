import { defineConfig } from "@playwright/test";

export const testDataDir = process.env.VBACK_PLAYWRIGHT_DATA_DIR || `/tmp/vback-playwright-${process.pid}`;
process.env.VBACK_PLAYWRIGHT_DATA_DIR = testDataDir;

export default defineConfig({
  testDir: "./e2e",
  timeout: 30_000,
  fullyParallel: false,
  workers: 1,
  use: {
    baseURL: "http://127.0.0.1:19990",
    locale: "zh-CN",
  },
  webServer: {
    command: "go run ../cmd/vback serve",
    url: "http://127.0.0.1:19990/api/v1/health",
    reuseExistingServer: false,
    timeout: 60_000,
    env: {
      VBACK_DATA_DIR: testDataDir,
      VBACK_LISTEN: "127.0.0.1:19990",
    },
  },
});
