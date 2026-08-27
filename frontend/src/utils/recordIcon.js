/** Stable accent colours for initials tiles — one picked from the title. */
const INITIALS_PALETTE = [
  "#4f46e5",
  "#0891b2",
  "#059669",
  "#d97706",
  "#dc2626",
  "#7c3aed",
  "#db2777",
  "#2563eb",
];

/**
 * @param {string | null | undefined} url
 * @returns {string | null}
 */
export function siteDomain(url) {
  const trimmed = url?.trim();
  if (!trimmed) return null;

  try {
    const withScheme = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
    return new URL(withScheme).hostname.replace(/^www\./i, "");
  } catch {
    return null;
  }
}

/**
 * @param {string | null | undefined} title
 * @returns {string}
 */
export function recordInitials(title) {
  const words = title?.trim().split(/\s+/).filter(Boolean) ?? [];
  if (words.length >= 2) {
    return `${words[0][0] ?? ""}${words[1][0] ?? ""}`.toUpperCase();
  }
  if (words.length === 1) {
    return words[0].slice(0, 2).toUpperCase();
  }
  return "?";
}

/**
 * @param {string | null | undefined} title
 */
export function initialsBackground(title) {
  const text = title?.trim() ?? "";
  let hash = 0;
  for (let i = 0; i < text.length; i += 1) {
    hash = (hash * 31 + text.charCodeAt(i)) | 0;
  }
  return INITIALS_PALETTE[Math.abs(hash) % INITIALS_PALETTE.length];
}

/**
 * @param {string | null | undefined} domain
 * @returns {string | null}
 */
export function faviconUrl(domain) {
  if (!domain) return null;
  return `https://www.google.com/s2/favicons?domain=${encodeURIComponent(domain)}&sz=128`;
}
