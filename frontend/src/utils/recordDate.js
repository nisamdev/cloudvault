/**
 * Dates as a register cares about them.
 *
 * A register's whole reason for existing is knowing when things run out, so a
 * date here is never just a string. "2028-04-30" tells you nothing you can act
 * on; "30 April 2028 · 1 year 8 months left" tells you whether to do something
 * today.
 */

const DAY = 86_400_000;

/** "30 April 2028" — the way it would be written on the document. */
export function formatRecordDate(value) {
  const date = parseDate(value);
  if (!date) return String(value ?? "");

  return date.toLocaleDateString(undefined, { day: "numeric", month: "long", year: "numeric" });
}

/**
 * A date on a document is a calendar day, not an instant.
 *
 * `new Date("2028-04-30")` is parsed as midnight **UTC**, so anywhere west of
 * Greenwich it reads back as the 29th — a permit would appear to expire a day
 * early, and "expires today" would show the day after it already had. A bare
 * date is therefore built as a local one.
 */
export function parseDate(value) {
  if (!value) return null;

  const plain = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value).trim());
  if (plain) {
    return new Date(Number(plain[1]), Number(plain[2]) - 1, Number(plain[3]));
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

/** Whole days from today, negative once the date has gone. */
export function daysUntil(value) {
  const date = parseDate(value);
  if (!date) return null;

  const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();

  return Math.round((startOfDay(date) - startOfDay(new Date())) / DAY);
}

/**
 * How long is left, in the largest unit that still says something useful.
 *
 * Years and months, not "612 days" — nobody plans a visa renewal in days.
 */
export function humanSpan(days) {
  const count = Math.abs(days);
  if (count === 0) return "today";
  if (count === 1) return "1 day";
  if (count < 45) return `${count} days`;

  const months = Math.round(count / 30.44);
  if (months < 12) return `${months} month${months === 1 ? "" : "s"}`;

  const years = Math.floor(months / 12);
  const rest = months % 12;
  const yearPart = `${years} year${years === 1 ? "" : "s"}`;

  return rest ? `${yearPart} ${rest} month${rest === 1 ? "" : "s"}` : yearPart;
}

/**
 * What a screen needs to say about an expiry.
 *
 * `elapsed` is only returned when the term's start is known. Drawing a
 * proportional bar without one would mean inventing a denominator, and a bar
 * that means nothing is worse than no bar.
 *
 * @param {string} value the date the thing runs out
 * @param {string} [from] the date it started, when the record knows it
 */
export function expiryState(value, from = null) {
  const date = parseDate(value);
  if (!date) return null;

  const days = daysUntil(value);
  const tone = days < 0 ? "expired" : days <= 30 ? "urgent" : days <= 90 ? "soon" : "fine";

  const state = {
    date,
    days,
    formatted: formatRecordDate(value),
    span: humanSpan(days),
    tone,
    label:
      days < 0
        ? `expired ${humanSpan(days)} ago`
        : days === 0
          ? "expires today"
          : `${humanSpan(days)} left`,
  };

  const start = parseDate(from);
  if (start && start < date) {
    const total = date - start;
    const gone = Date.now() - start;
    state.elapsed = Math.min(1, Math.max(0, gone / total));
  }

  return state;
}
