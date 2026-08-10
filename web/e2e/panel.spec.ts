import { expect, test } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { testDataDir } from "../playwright.config";

test("首次设置和响应式布局", async ({ page }) => {
  const token = (await readFile(`${testDataDir}/setup-token`, "utf8")).trim();
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "保护你的备份面板" })).toBeVisible();
  await page.getByLabel("一次性 Setup Token").fill(token);
  await page.getByLabel("管理员密码").fill("playwright-secure-password");
  await page.getByLabel("确认密码").fill("playwright-secure-password");
  await page.getByRole("button", { name: "继续配置" }).click();
  await expect(page.getByRole("heading", { name: "连接加密备份仓库" })).toBeVisible();

  for (const width of [360, 768, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    for (const colorScheme of ["light", "dark"] as const) {
      await page.emulateMedia({ colorScheme });
      await expect(page.locator("body")).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    }
  }
});
