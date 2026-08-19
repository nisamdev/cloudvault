import { describe, it, expect } from "vitest";
import { formatFileSize, formatRelativeDate, fileIcon, dateGroup, groupByDate } from "./formatting";

describe("formatFileSize", () => {
  it("formats zero", () => expect(formatFileSize(0)).toBe("0 B"));
  it("formats bytes without decimals", () => expect(formatFileSize(512)).toBe("512 B"));
  it("formats kilobytes", () => expect(formatFileSize(2048)).toBe("2.0 KB"));
  it("formats megabytes", () => expect(formatFileSize(5 * 1024 * 1024)).toBe("5.0 MB"));
  it("caps at terabytes", () => expect(formatFileSize(1024 ** 5)).toContain("TB"));
  it("returns empty for null", () => expect(formatFileSize(null)).toBe(""));
});

describe("formatRelativeDate", () => {
  it("labels today", () => expect(formatRelativeDate(new Date().toISOString())).toBe("Today"));

  it("labels yesterday", () => {
    const d = new Date();
    d.setDate(d.getDate() - 1);
    expect(formatRelativeDate(d.toISOString())).toBe("Yesterday");
  });

  it("counts days within the week", () => {
    const d = new Date();
    d.setDate(d.getDate() - 3);
    expect(formatRelativeDate(d.toISOString())).toBe("3 days ago");
  });

  it("returns empty for no value", () => expect(formatRelativeDate(null)).toBe(""));
});

describe("fileIcon", () => {
  it("picks an image icon by file_type", () => {
    expect(fileIcon({ file_type: "image", mime_type: "image/png" }).icon).toBe("fa-file-image");
  });

  it("picks a pdf icon", () => {
    expect(fileIcon({ file_type: "file", mime_type: "application/pdf" }).icon).toBe("fa-file-pdf");
  });

  it("falls back to a generic icon", () => {
    expect(fileIcon({ file_type: "file", mime_type: "application/x-thing" }).icon).toBe("fa-file");
  });
});

describe("dateGroup", () => {
  const daysAgo = (n) => {
    const d = new Date();
    d.setDate(d.getDate() - n);
    return d.toISOString();
  };

  it("labels today and yesterday", () => {
    expect(dateGroup(daysAgo(0))).toBe("Today");
    expect(dateGroup(daysAgo(1))).toBe("Yesterday");
  });

  it("groups the rest of the week together", () => {
    expect(dateGroup(daysAgo(3))).toBe("Earlier this week");
  });

  it("falls back to the month for older dates", () => {
    const older = new Date();
    older.setDate(older.getDate() - 40);
    const label = dateGroup(older.toISOString());
    expect(label).not.toBe("Earlier this week");
    expect(label.length).toBeGreaterThan(2);
  });

  it("handles a missing date", () => {
    expect(dateGroup(null)).toBe("Undated");
  });
});

describe("groupByDate", () => {
  it("keeps incoming order and buckets by label", () => {
    const now = new Date().toISOString();
    const yesterday = new Date(Date.now() - 86_400_000).toISOString();

    const groups = groupByDate([
      { id: 1, created_at: now },
      { id: 2, created_at: now },
      { id: 3, created_at: yesterday },
    ]);

    expect(groups.map((g) => g.label)).toEqual(["Today", "Yesterday"]);
    expect(groups[0].items).toHaveLength(2);
    expect(groups[1].items).toHaveLength(1);
  });

  it("returns nothing for an empty list", () => {
    expect(groupByDate([])).toEqual([]);
  });
});
