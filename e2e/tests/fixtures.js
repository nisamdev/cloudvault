import { test as base, expect } from "@playwright/test";
import { authFile } from "./helpers.js";

/**
 * The access token lives only in memory. Each new page restores the session by
 * posting the httpOnly refresh cookie, and the API rotates that cookie. Reusing
 * the previous value is treated as theft and revokes the chain, so every test
 * writes the cookie it finished with for the next one.
 *
 * Safe only because the config runs a single worker.
 */
export const test = base.extend({
  context: async ({ browser }, use) => {
    const context = await browser.newContext({ storageState: authFile });
    await use(context);
    // A crashed browser closes the context before we get here. Saving is best
    // effort; the test failure is the one worth reading.
    await context.storageState({ path: authFile }).catch(() => {});
    await context.close().catch(() => {});
  },
});

export { expect };
