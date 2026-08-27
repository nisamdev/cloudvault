import { WORDS } from "@/utils/wordlist";

/**
 * Making passwords.
 *
 * Entirely in the browser, with crypto.getRandomValues. A password you looked
 * at and rejected should never have existed anywhere but on your screen, so
 * nothing here touches the network and nothing is generated on the server.
 *
 * Strength is reported as how long it would take to guess rather than as a
 * coloured bar, because "strong" is not a claim anyone can check and "four
 * hundred years" is.
 */

const UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const LOWER = "abcdefghijkmnopqrstuvwxyz";
const DIGITS = "23456789";
const SYMBOLS = "!@#$%^&*()-_=+[]{};:,.?";

// The characters people mistranscribe. Excluded by default because a password
// often has to be read off a screen and typed into a television.
const AMBIGUOUS_UPPER = "IO";
const AMBIGUOUS_LOWER = "l";
const AMBIGUOUS_DIGITS = "01";

export const DEFAULTS = {
  length: 20,
  upper: true,
  lower: true,
  digits: true,
  symbols: true,
  avoidAmbiguous: true,
  // Six, not five: five comes out at about 25 years of guessing and six at
  // thousands. The extra word costs nothing to remember and the default is
  // what most passphrases will actually be.
  words: 6,
  separator: "-",
  capitalise: false,
  addNumber: true,
};

/**
 * Random integer below `max`, without modulo bias.
 *
 * Taking a random byte modulo 26 makes the first six letters likelier than the
 * rest. Rejecting the values that would skew it costs a few extra draws and
 * removes the lean entirely.
 */
export function randomBelow(max) {
  if (max <= 0) throw new Error("max must be positive");

  const limit = Math.floor(0xffffffff / max) * max;
  const buffer = new Uint32Array(1);

  for (;;) {
    crypto.getRandomValues(buffer);
    if (buffer[0] < limit) return buffer[0] % max;
  }
}

function pick(pool) {
  return pool[randomBelow(pool.length)];
}

/** The characters a given set of options allows. */
export function alphabet(options = {}) {
  const { upper, lower, digits, symbols, avoidAmbiguous } = { ...DEFAULTS, ...options };
  let pool = "";

  if (upper) pool += avoidAmbiguous ? UPPER : UPPER + AMBIGUOUS_UPPER;
  if (lower) pool += avoidAmbiguous ? LOWER : LOWER + AMBIGUOUS_LOWER;
  if (digits) pool += avoidAmbiguous ? DIGITS : DIGITS + AMBIGUOUS_DIGITS;
  if (symbols) pool += SYMBOLS;

  return pool;
}

/**
 * A random password.
 *
 * Guarantees at least one character from every class that was asked for —
 * otherwise a twenty-character password can come out with no digit in it and be
 * rejected by the site you were making it for. The guaranteed characters are
 * placed at random positions, not at the front.
 */
export function randomPassword(options = {}) {
  const settings = { ...DEFAULTS, ...options };
  const pool = alphabet(settings);
  if (!pool) throw new Error("Choose at least one kind of character.");

  const length = Math.max(4, Math.min(128, settings.length));
  const required = [];
  const { avoidAmbiguous } = settings;

  if (settings.upper) required.push(pick(avoidAmbiguous ? UPPER : UPPER + AMBIGUOUS_UPPER));
  if (settings.lower) required.push(pick(avoidAmbiguous ? LOWER : LOWER + AMBIGUOUS_LOWER));
  if (settings.digits) required.push(pick(avoidAmbiguous ? DIGITS : DIGITS + AMBIGUOUS_DIGITS));
  if (settings.symbols) required.push(pick(SYMBOLS));

  const characters = [];
  for (let i = 0; i < length; i += 1) characters.push(pick(pool));

  // Drop the required ones into distinct random slots.
  const slots = [];
  while (slots.length < Math.min(required.length, length)) {
    const slot = randomBelow(length);
    if (!slots.includes(slot)) slots.push(slot);
  }
  slots.forEach((slot, i) => {
    characters[slot] = required[i];
  });

  return characters.join("");
}

/** A passphrase: words a person can actually retype. */
export function passphrase(options = {}) {
  const settings = { ...DEFAULTS, ...options };
  const count = Math.max(3, Math.min(12, settings.words));

  const chosen = [];
  for (let i = 0; i < count; i += 1) {
    const word = WORDS[randomBelow(WORDS.length)];
    chosen.push(settings.capitalise ? word[0].toUpperCase() + word.slice(1) : word);
  }

  if (settings.addNumber) {
    // On the end of a random word rather than always the last, so its position
    // carries a little information too.
    const at = randomBelow(chosen.length);
    chosen[at] += String(randomBelow(100)).padStart(2, "0");
  }

  return chosen.join(settings.separator);
}

/**
 * Bits of entropy — how many guesses an attacker faces, expressed as a power of
 * two, assuming they know exactly how the password was made. That assumption is
 * deliberately generous to the attacker; it is the only honest way to count.
 */
export function entropyBits(mode, options = {}) {
  const settings = { ...DEFAULTS, ...options };

  if (mode === "passphrase") {
    const count = Math.max(3, Math.min(12, settings.words));
    let bits = count * Math.log2(WORDS.length);
    // A two-digit number in one of `count` positions.
    if (settings.addNumber) bits += Math.log2(100 * count);
    // Capitalising every word is a fixed rule, not a choice per word, so it
    // adds nothing an attacker has to guess.
    return bits;
  }

  const pool = alphabet(settings).length;
  if (!pool) return 0;

  return Math.max(4, Math.min(128, settings.length)) * Math.log2(pool);
}

/**
 * How long the guessing would take, as words.
 *
 * Assumes an offline attacker at ten billion guesses a second — the right order
 * of magnitude for a stolen database and commodity hardware, and pessimistic
 * enough to be worth trusting.
 */
const GUESSES_PER_SECOND = 1e10;

export function timeToGuess(bits) {
  if (!bits) return { label: "instantly", tone: "bad" };

  // Half the keyspace on average.
  const seconds = Math.pow(2, bits - 1) / GUESSES_PER_SECOND;

  const tone = bits < 50 ? "bad" : bits < 70 ? "fair" : bits < 90 ? "good" : "strong";

  const spans = [
    [1, "less than a second"],
    [60, "seconds"],
    [3600, "minutes"],
    [86400, "hours"],
    [2592000, "days"],
    [31536000, "months"],
  ];

  for (const [limit, unit] of spans) {
    if (seconds < limit) {
      if (unit === "less than a second") return { label: unit, tone };

      const value = Math.max(1, Math.round(seconds / (limit / 60)));
      return { label: `about ${value} ${value === 1 ? unit.replace(/s$/, "") : unit}`, tone };
    }
  }

  const years = seconds / 31536000;
  if (years < 1000) return { label: `about ${Math.round(years)} years`, tone };
  if (years < 1e6) return { label: `about ${Math.round(years / 1000)} thousand years`, tone };
  if (years < 1e9) return { label: `about ${Math.round(years / 1e6)} million years`, tone };
  if (years < 1e12) return { label: `about ${Math.round(years / 1e9)} billion years`, tone };

  return { label: "longer than the universe has existed", tone };
}

/** Everything a screen needs to describe a password it just made. */
export function describe(mode, options) {
  const bits = entropyBits(mode, options);

  return { bits: Math.round(bits), ...timeToGuess(bits) };
}

export function generate(mode, options) {
  return mode === "passphrase" ? passphrase(options) : randomPassword(options);
}
