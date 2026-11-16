import { defineConfig, devices } from "@playwright/test";

// Compose runs this container in the web service's network namespace and points
// here. 127.0.0.1 is a trustworthy origin, so Chromium keeps the Secure
// refresh cookie a production-mode API sets. http://web:5173 is not, and the
// cookie is silently dropped.
const baseURL = process.env.PLAYWRIGHT_BASE_URL || "http://127.0.0.1:5173";

export default defineConfig({
  testDir: "./tests",
  // Login is throttled (5 / 20s per IP), and a refresh cookie rotates on every
  // use. One worker keeps those from tripping each other.
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: "list",
  use: {
    baseURL,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "setup", testMatch: /auth\.setup\.js/ },
    {
      name: "guest",
      testMatch: /auth\.spec\.js/,
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "chromium",
      testIgnore: /auth\.(setup|spec)\.js/,
      dependencies: ["setup"],
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
