import { expect, test } from "@playwright/test";
import { owner, signIn } from "./helpers.js";

test("a guest is sent to the sign-in page", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveURL(/\/login/);
  await expect(page.getByRole("heading", { name: "CloudVault" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Sign In" })).toBeVisible();
});

test("a wrong password is rejected", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("Email Address").fill(owner.email);
  await page.getByLabel("Password", { exact: true }).fill("not-the-password");
  await page.getByRole("button", { name: "Sign In" }).click();

  await expect(page.getByRole("alert")).toHaveText("That email or password is incorrect.");
  await expect(page).toHaveURL(/\/login/);
});

test("the seeded owner can sign in and sign out", async ({ page }) => {
  await signIn(page);
  await expect(page.getByRole("banner").getByText("The Smith Family")).toBeVisible();
  await expect(page.getByRole("banner").getByText("Dad Smith")).toBeVisible();

  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page).toHaveURL(/\/login/);
  await expect(page.getByRole("button", { name: "Sign In" })).toBeVisible();
});

test("a new account lands in an empty vault", async ({ page }) => {
  const email = `e2e-${Date.now()}@example.com`;

  await page.goto("/register");
  await page.getByLabel("Full name").fill("E2E Tester");
  await page.getByLabel("Email address").fill(email);
  await page.getByLabel("Password", { exact: true }).fill("password123");
  await page.getByLabel("Confirm password").fill("password123");
  await page.getByRole("checkbox", { name: /Terms of Service/ }).check();
  await page.getByRole("button", { name: "Create account" }).click();

  await expect(page.getByRole("heading", { level: 1, name: "My Files" })).toBeVisible();
  await expect(page.getByRole("banner").getByText("E2E Tester")).toBeVisible();
});

test("an unknown address shows the not-found page", async ({ page }) => {
  await page.goto("/does-not-exist");
  await expect(page.getByRole("heading", { name: "Page not found" })).toBeVisible();
});
