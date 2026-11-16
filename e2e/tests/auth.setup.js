import { test as setup } from "@playwright/test";
import { authFile, signIn } from "./helpers.js";

setup("sign in as the seeded owner", async ({ page }) => {
  await signIn(page);
  await page.context().storageState({ path: authFile });
});
