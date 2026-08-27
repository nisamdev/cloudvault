import { describe, expect, it } from "vitest";
import { faviconUrl, recordInitials, siteDomain } from "./recordIcon";

describe("siteDomain", () => {
  it("pulls the hostname and drops www", () => {
    expect(siteDomain("https://www.netflix.com/browse")).toBe("netflix.com");
    expect(siteDomain("gmail.com")).toBe("gmail.com");
  });

  it("returns null for garbage", () => {
    expect(siteDomain("")).toBeNull();
    expect(siteDomain("   ")).toBeNull();
  });
});

describe("recordInitials", () => {
  it("uses two words when available", () => {
    expect(recordInitials("British Gas")).toBe("BG");
  });

  it("uses the first two letters of one word", () => {
    expect(recordInitials("Netflix")).toBe("NE");
  });
});

describe("faviconUrl", () => {
  it("points at Google's favicon service", () => {
    expect(faviconUrl("netflix.com")).toContain("netflix.com");
  });
});
