import { expect, test } from "./fixtures.js";

test("the sidebar opens each main screen", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1, name: "My Files" })).toBeVisible();

  const screens = [
    ["Recent", "Recent"],
    // The gallery heading is the open album. With no album yet it falls back
    // to "Photo Gallery".
    ["Photos", /^(All photos|Photo Gallery)$/],
    ["Shared", "Shared"],
    ["Family records", "Family records"],
    ["Household", "Household"],
    ["Private", "Private"],
    ["Tools", "Tools"],
    ["Trash", "Trash"],
    ["Settings", "Settings"],
    ["My Files", "My Files"],
  ];

  for (const [link, heading] of screens) {
    await page.getByRole("link", { name: link, exact: true }).click();
    await expect(page.getByRole("heading", { level: 1, name: heading, exact: true })).toBeVisible();
  }
});
