/**
 * Which half of the cabinet a record lives in.
 *
 * A passport is about a person; a boiler contract is about the house. The
 * template says which, and everything that needs to link back to a listing —
 * breadcrumbs, the cancel button, where saving returns you — asks here rather
 * than guessing.
 */
export const SECTIONS = {
  people: { label: "Family records", route: "family-records" },
  household: { label: "Household", route: "household" },
};

export function sectionFor(group) {
  return SECTIONS[group] ?? SECTIONS.people;
}

/** The breadcrumb back to wherever this record is filed. */
export function sectionCrumb(group) {
  const section = sectionFor(group);

  return { label: section.label, to: { name: section.route } };
}
