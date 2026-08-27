/**
 * A colour per kind of record.
 *
 * Distinct from the per-title colour on the initials tile: that one identifies
 * a record, this one identifies what sort of thing it is. Chosen so the two
 * that hold passwords sit together at the cool end and the ones that run out —
 * permits, vehicles — carry warmer, more alert hues.
 */
const ACCENTS = {
  login: "#4f46e5",
  service_account: "#2563eb",
  immigration: "#7c3aed",
  person: "#0891b2",
  property: "#d97706",
  vehicle: "#0d9488",
  money: "#059669",
  subscription: "#db2777",
  emergency: "#dc2626",
};

const FALLBACK = "#64748b";

export function recordTypeAccent(type) {
  return ACCENTS[type] ?? FALLBACK;
}

/** A wash of the accent, for the tile behind an icon. */
export function recordTypeTint(type) {
  return `${recordTypeAccent(type)}14`;
}
