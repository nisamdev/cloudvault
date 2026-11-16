import { expect, test } from "./fixtures.js";

test("creates a folder, uploads a file into it, and trashes both", async ({ page }) => {
  const stamp = Date.now();
  const folderName = `E2E folder ${stamp}`;
  const fileName = `e2e-note-${stamp}.txt`;

  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1, name: "My Files" })).toBeVisible();

  await page.getByRole("button", { name: "New folder" }).click();
  await page.getByPlaceholder("Folder name").fill(folderName);
  await page.getByRole("button", { name: "Add" }).click();
  await expect(page.getByRole("button", { name: folderName, exact: true }).first()).toBeVisible();

  await page.getByRole("button", { name: folderName, exact: true }).first().click();
  await expect(page.getByRole("heading", { level: 1, name: folderName })).toBeVisible();

  await page.getByLabel("Choose files to upload").setInputFiles({
    name: fileName,
    mimeType: "text/plain",
    buffer: Buffer.from("Playwright put this here.\n"),
  });

  await expect(page.getByRole("button", { name: fileName, exact: true })).toBeVisible();

  // The success toast sits on the bulk-action bar and swallows the click.
  const dismiss = page.getByRole("button", { name: "Dismiss" });
  if (await dismiss.isVisible()) await dismiss.click();

  await page.getByLabel("Search files").fill(fileName);
  await expect(
    page.getByRole("heading", { level: 1, name: `Results for "${fileName}"` }),
  ).toBeVisible();
  await expect(page.getByRole("button", { name: fileName, exact: true })).toBeVisible();

  // Search hides the folder rows, so clear it and throw the note away from
  // inside the folder, then the folder itself from the root.
  await page.getByLabel("Search files").fill("");
  await expect(page.getByRole("heading", { level: 1, name: folderName })).toBeVisible();

  await page.getByRole("button", { name: `Select ${fileName}` }).click();
  await page.getByRole("button", { name: "Move to trash" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Move to trash" }).click();
  await expect(page.getByRole("button", { name: fileName, exact: true })).toHaveCount(0);

  await page.getByRole("button", { name: "All files" }).first().click();
  await expect(page.getByRole("heading", { level: 1, name: "My Files" })).toBeVisible();
  await page.getByRole("button", { name: `Select ${folderName}` }).click();
  await page.getByRole("button", { name: "Move to trash" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Move to trash" }).click();
  await expect(page.getByRole("button", { name: folderName, exact: true })).toHaveCount(0);
});
