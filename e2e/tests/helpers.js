import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));

/** Saved refresh cookie for the seeded owner. Rotated by the signed-in fixture. */
export const authFile = path.join(here, "../.auth/dad.json");

export const owner = {
  email: process.env.E2E_EMAIL || "dad@smith.com",
  password: process.env.E2E_PASSWORD || "password123",
};

/** Signs in through the form and waits until My Files is on screen. */
export async function signIn(page, credentials = owner) {
  await page.goto("/login");
  await page.getByLabel("Email Address").fill(credentials.email);
  await page.getByLabel("Password", { exact: true }).fill(credentials.password);
  await page.getByRole("button", { name: "Sign In" }).click();
  await page.getByRole("heading", { level: 1, name: "My Files" }).waitFor();
}
