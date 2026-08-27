/**
 * A colour per kind of record.
 *
 * Distinct from the per-title colour on the initials tile: that one identifies
 * a record, this one identifies what sort of thing it is. Chosen so the two
 * that hold passwords sit together at the cool end and the ones that run out —
 * permits, vehicles — carry warmer, more alert hues.
 */
const ACCENTS = {
  // The house's affairs: passwords at the cool end, money and property warm.
  login: "#4f46e5",
  service_account: "#2563eb",
  property: "#d97706",
  vehicle: "#0d9488",
  money: "#059669",
  subscription: "#db2777",
  emergency: "#dc2626",

  // A person's documents. Each is a different colour on purpose — a shelf of
  // these is read by colour and shape before it is read by name, and two
  // passports next to two licences should not look like four of the same
  // thing.
  person: "#0891b2",
  passport: "#1d4ed8",
  driving_licence: "#0f766e",
  birth_certificate: "#a16207",
  health_card: "#be123c",
  immigration: "#7c3aed",
  document: "#57534e",
};

const FALLBACK = "#64748b";

export function recordTypeAccent(type) {
  return ACCENTS[type] ?? FALLBACK;
}

/** A wash of the accent, for the tile behind an icon. */
export function recordTypeTint(type) {
  return `${recordTypeAccent(type)}1f`;
}
