/** Human-readable file size. 1024-based, matching what OS file browsers show. */
export function formatFileSize(bytes) {
  if (bytes === null || bytes === undefined) return "";
  if (bytes === 0) return "0 B";

  const units = ["B", "KB", "MB", "GB", "TB"];
  const exponent = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  const value = bytes / 1024 ** exponent;

  // Whole numbers for bytes, one decimal above that.
  return `${exponent === 0 ? value : value.toFixed(1)} ${units[exponent]}`;
}

/** "Today", "Yesterday", or a short date — the grouping PATTERNS.md specifies. */
export function formatRelativeDate(value) {
  if (!value) return "";

  const date = new Date(value);
  const today = new Date();
  const startOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const startOfDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const dayDiff = Math.round((startOfToday - startOfDate) / 86_400_000);

  if (dayDiff === 0) return "Today";
  if (dayDiff === 1) return "Yesterday";
  if (dayDiff < 7) return `${dayDiff} days ago`;

  return date.toLocaleDateString(undefined, {
    day: "numeric",
    month: "short",
    year: date.getFullYear() === today.getFullYear() ? undefined : "numeric",
  });
}

/** Font Awesome icon + colour for a file, chosen by mime type. */
export function fileIcon(file) {
  const mime = file.mime_type ?? "";

  if (file.file_type === "image") return { icon: "fa-file-image", className: "text-secondary-600" };
  if (mime === "application/pdf") return { icon: "fa-file-pdf", className: "text-error-500" };
  if (mime.includes("word") || mime.includes("document")) return { icon: "fa-file-word", className: "text-info-500" };
  if (mime.includes("sheet") || mime.includes("excel")) return { icon: "fa-file-excel", className: "text-success-500" };
  if (mime.includes("zip") || mime.includes("compressed")) return { icon: "fa-file-zipper", className: "text-warning-500" };
  if (mime.startsWith("video/")) return { icon: "fa-file-video", className: "text-accent-500" };
  if (mime.startsWith("audio/")) return { icon: "fa-file-audio", className: "text-info-500" };
  if (mime.startsWith("text/")) return { icon: "fa-file-lines", className: "text-gray-500" };

  return { icon: "fa-file", className: "text-gray-400" };
}

/**
 * Section heading a photo belongs under in the gallery.
 * Today / Yesterday / This week / month / month + year, per the implementation
 * guide's date grouping.
 */
export function dateGroup(value) {
  if (!value) return "Undated";

  const date = new Date(value);
  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startOfDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const dayDiff = Math.round((startOfToday - startOfDate) / 86_400_000);

  if (dayDiff === 0) return "Today";
  if (dayDiff === 1) return "Yesterday";
  if (dayDiff < 7) return "Earlier this week";

  const sameYear = date.getFullYear() === now.getFullYear();
  return date.toLocaleDateString(undefined, {
    month: "long",
    year: sameYear ? undefined : "numeric",
  });
}

/** Groups items into [{ label, items }] preserving the incoming order. */
export function groupByDate(items, key = "created_at") {
  const groups = [];
  const index = new Map();

  for (const item of items) {
    const label = dateGroup(item[key]);

    if (!index.has(label)) {
      index.set(label, { label, items: [] });
      groups.push(index.get(label));
    }

    index.get(label).items.push(item);
  }

  return groups;
}
