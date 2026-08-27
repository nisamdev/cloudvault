import { describe, expect, it } from "vitest";
import {
  DEFAULTS,
  alphabet,
  describe as summarise,
  entropyBits,
  generate,
  passphrase,
  randomBelow,
  randomPassword,
  timeToGuess,
} from "@/utils/passwordGenerator";
import { WORDS } from "@/utils/wordlist";

describe("randomBelow", () => {
  it("stays inside the range", () => {
    for (let i = 0; i < 500; i += 1) {
      const n = randomBelow(7);
      expect(n).toBeGreaterThanOrEqual(0);
      expect(n).toBeLessThan(7);
    }
  });

  // The reason for rejection sampling: a byte taken modulo 26 makes the first
  // six letters likelier than the rest, which quietly costs entropy.
  it("does not lean towards the low end", () => {
    const counts = new Array(5).fill(0);
    for (let i = 0; i < 20_000; i += 1) counts[randomBelow(5)] += 1;

    const expected = 20_000 / 5;
    counts.forEach((count) => {
      expect(Math.abs(count - expected) / expected).toBeLessThan(0.15);
    });
  });

  it("refuses a range of nothing", () => {
    expect(() => randomBelow(0)).toThrow();
  });
});

describe("randomPassword", () => {
  it("is the length that was asked for", () => {
    expect(randomPassword({ length: 32 })).toHaveLength(32);
    expect(randomPassword({ length: 8 })).toHaveLength(8);
  });

  // A twenty-character password with no digit in it gets rejected by the site
  // you made it for, which is how people end up choosing their own.
  it("includes every kind of character that was asked for", () => {
    for (let i = 0; i < 40; i += 1) {
      const password = randomPassword({ length: 12 });
      expect(password).toMatch(/[A-Z]/);
      expect(password).toMatch(/[a-z]/);
      expect(password).toMatch(/[0-9]/);
      expect(password).toMatch(/[^A-Za-z0-9]/);
    }
  });

  it("leaves out the classes that were turned off", () => {
    const password = randomPassword({ length: 24, symbols: false, digits: false });

    expect(password).toMatch(/^[A-Za-z]+$/);
  });

  it("drops the characters people mistranscribe", () => {
    for (let i = 0; i < 40; i += 1) {
      expect(randomPassword({ length: 40 })).not.toMatch(/[IOl01]/);
    }
  });

  it("allows them back when asked", () => {
    const pool = alphabet({ avoidAmbiguous: false });

    expect(pool).toContain("I");
    expect(pool).toContain("0");
  });

  it("does not put the guaranteed characters in the same place every time", () => {
    const firsts = new Set();
    for (let i = 0; i < 60; i += 1) firsts.add(randomPassword({ length: 10 })[0]);

    expect(firsts.size).toBeGreaterThan(3);
  });

  it("refuses to make a password out of nothing", () => {
    expect(() =>
      randomPassword({ upper: false, lower: false, digits: false, symbols: false }),
    ).toThrow(/at least one/);
  });

  it("is different every time", () => {
    const made = new Set();
    for (let i = 0; i < 50; i += 1) made.add(randomPassword());

    expect(made.size).toBe(50);
  });
});

describe("passphrase", () => {
  it("uses the number of words asked for", () => {
    expect(passphrase({ words: 4, addNumber: false }).split("-")).toHaveLength(4);
    expect(passphrase({ words: 7, addNumber: false }).split("-")).toHaveLength(7);
  });

  it("only uses words from the list", () => {
    const words = passphrase({ words: 6, addNumber: false }).split("-");

    words.forEach((word) => expect(WORDS).toContain(word));
  });

  it("honours the separator", () => {
    expect(passphrase({ words: 4, separator: ".", addNumber: false })).toMatch(
      /^[a-z]+\.[a-z]+\.[a-z]+\.[a-z]+$/,
    );
  });

  it("capitalises when asked, and not otherwise", () => {
    expect(passphrase({ words: 4, capitalise: true, addNumber: false })).toMatch(/^[A-Z]/);
    expect(passphrase({ words: 4, capitalise: false, addNumber: false })).toMatch(/^[a-z]/);
  });

  it("adds a number somewhere, not always at the end", () => {
    const positions = new Set();
    for (let i = 0; i < 60; i += 1) {
      const parts = passphrase({ words: 4, addNumber: true }).split("-");
      positions.add(parts.findIndex((p) => /\d/.test(p)));
    }

    expect(positions.size).toBeGreaterThan(1);
  });
});

describe("the wordlist", () => {
  it("has no duplicates, which would quietly cost entropy", () => {
    expect(new Set(WORDS).size).toBe(WORDS.length);
  });

  it("is all lowercase letters — nothing to spell out over the phone", () => {
    WORDS.forEach((word) => expect(word).toMatch(/^[a-z]+$/));
  });

  // The strength shown on screen is computed from this number, so it is worth
  // asserting rather than assuming.
  it("is big enough for the strength it claims", () => {
    expect(WORDS.length).toBeGreaterThanOrEqual(1500);
    expect(Math.log2(WORDS.length)).toBeGreaterThan(10);
  });

  it("has no word so long nobody would retype it", () => {
    WORDS.forEach((word) => expect(word.length).toBeLessThanOrEqual(9));
  });
});

describe("entropyBits", () => {
  it("counts a random password as length times the log of the pool", () => {
    const options = { length: 10, symbols: false, digits: false };
    const pool = alphabet(options);

    // 24 upper + 25 lower, once I, O and l have gone.
    expect(pool).toHaveLength(49);
    expect(entropyBits("random", options)).toBeCloseTo(10 * Math.log2(pool.length), 5);
  });

  it("counts a passphrase from the size of the wordlist", () => {
    const bits = entropyBits("passphrase", { words: 5, addNumber: false });

    expect(bits).toBeCloseTo(5 * Math.log2(WORDS.length), 5);
  });

  it("gives more for more words and more length", () => {
    expect(entropyBits("passphrase", { words: 6 })).toBeGreaterThan(
      entropyBits("passphrase", { words: 4 }),
    );
    expect(entropyBits("random", { length: 24 })).toBeGreaterThan(
      entropyBits("random", { length: 12 }),
    );
  });

  // Capitalising every word is a rule, not a per-word choice, so it adds
  // nothing an attacker has to guess. Claiming otherwise would be flattery.
  it("does not pretend capitalising adds strength", () => {
    expect(entropyBits("passphrase", { words: 5, capitalise: true, addNumber: false })).toBe(
      entropyBits("passphrase", { words: 5, capitalise: false, addNumber: false }),
    );
  });

  it("is zero when nothing is allowed", () => {
    expect(entropyBits("random", { upper: false, lower: false, digits: false, symbols: false }))
      .toBe(0);
  });
});

describe("timeToGuess", () => {
  it("says instantly when there is nothing to guess", () => {
    expect(timeToGuess(0).label).toBe("instantly");
  });

  it("grows with the bits", () => {
    expect(timeToGuess(30).label).not.toBe(timeToGuess(80).label);
    expect(timeToGuess(200).label).toMatch(/universe/);
  });

  it("rates a short password badly and a long one well", () => {
    expect(timeToGuess(entropyBits("random", { length: 6 })).tone).toBe("bad");
    expect(timeToGuess(entropyBits("random", { length: 24 })).tone).toBe("strong");
  });

  // A password manager's defaults should not need adjusting to be safe. The
  // random default is far past anything guessable; the passphrase default trades
  // some of that for being memorable, and lands in thousands of years.
  it("needs no adjusting to be safe out of the box", () => {
    expect(summarise("random", DEFAULTS).tone).toBe("strong");

    const words = summarise("passphrase", DEFAULTS);
    expect(words.bits).toBeGreaterThan(70);
    expect(["good", "strong"]).toContain(words.tone);
    expect(words.label).toMatch(/thousand years|million years|billion years|universe/);
  });
});

describe("generate", () => {
  it("picks the right maker for the mode", () => {
    expect(generate("passphrase", { words: 4 }).split("-").length).toBeGreaterThanOrEqual(4);
    expect(generate("random", { length: 16 })).toHaveLength(16);
  });
});
