import { describe, expect, it } from "vitest";
import { daysUntil, expiryState, formatRecordDate, humanSpan } from "@/utils/recordDate";

const inDays = (n) => {
  const d = new Date();
  d.setDate(d.getDate() + n);
  return d.toISOString().slice(0, 10);
};

describe("formatRecordDate", () => {
  it("writes a date the way it appears on the document", () => {
    expect(formatRecordDate("2028-04-30")).toMatch(/2028/);
    expect(formatRecordDate("2028-04-30")).toMatch(/April/);
  });

  it("hands back anything it cannot read, rather than showing nothing", () => {
    expect(formatRecordDate("sometime next year")).toBe("sometime next year");
    expect(formatRecordDate("")).toBe("");
  });
});

describe("humanSpan", () => {
  // Nobody plans a visa renewal in days.
  it("uses the largest unit that still says something useful", () => {
    expect(humanSpan(0)).toBe("today");
    expect(humanSpan(1)).toBe("1 day");
    expect(humanSpan(20)).toBe("20 days");
    expect(humanSpan(90)).toBe("3 months");
    expect(humanSpan(365)).toBe("1 year");
    expect(humanSpan(612)).toBe("1 year 8 months");
  });

  it("reads the same whether the date is ahead or behind", () => {
    expect(humanSpan(-90)).toBe(humanSpan(90));
  });
});

describe("expiryState", () => {
  it("counts the days left", () => {
    expect(daysUntil(inDays(10))).toBe(10);
    expect(daysUntil(inDays(-3))).toBe(-3);
  });

  it("says how long is left, in words", () => {
    expect(expiryState(inDays(400)).label).toBe("1 year 1 month left");
    expect(expiryState(inDays(0)).label).toBe("expires today");
    expect(expiryState(inDays(-40)).label).toMatch(/^expired .* ago$/);
  });

  // Semantic colour is reserved for this one thing, so the thresholds decide
  // what the register is allowed to shout about.
  it("escalates as the date approaches", () => {
    expect(expiryState(inDays(400)).tone).toBe("fine");
    expect(expiryState(inDays(60)).tone).toBe("soon");
    expect(expiryState(inDays(10)).tone).toBe("urgent");
    expect(expiryState(inDays(-1)).tone).toBe("expired");
  });

  // A bar needs a denominator. Inventing one would be decoration pretending to
  // be information.
  it("only works out how far through the term it is when the start is known", () => {
    expect(expiryState(inDays(365)).elapsed).toBeUndefined();

    const halfway = expiryState(inDays(180), inDays(-180));
    expect(halfway.elapsed).toBeGreaterThan(0.45);
    expect(halfway.elapsed).toBeLessThan(0.55);
  });

  it("keeps the bar inside its track when the date has gone", () => {
    expect(expiryState(inDays(-10), inDays(-100)).elapsed).toBe(1);
  });

  it("has nothing to say about a date it cannot read", () => {
    expect(expiryState("not a date")).toBeNull();
    expect(expiryState(null)).toBeNull();
  });
});
