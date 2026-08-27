/**
 * Puts text on the clipboard.
 *
 * navigator.clipboard only exists in a secure context, and CloudVault is
 * deliberately reached over a LAN address and a tunnel as well as localhost —
 * so on the very machines where copying a policy number matters most, the
 * modern API is simply absent. The old selection trick still works everywhere.
 *
 * @returns {Promise<boolean>} whether the text actually made it.
 */
export async function copyText(text) {
  const value = String(text ?? "");
  if (!value) return false;

  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(value);
      return true;
    } catch {
      // Denied, or not a secure context after all. Fall through.
    }
  }

  return legacyCopy(value);
}

function legacyCopy(value) {
  const field = document.createElement("textarea");
  field.value = value;
  // Off-screen rather than hidden: a field with display:none cannot be selected.
  field.setAttribute("readonly", "");
  field.style.position = "fixed";
  field.style.top = "-1000px";
  field.style.opacity = "0";

  document.body.appendChild(field);

  try {
    field.select();
    field.setSelectionRange(0, value.length);
    return document.execCommand("copy");
  } catch {
    return false;
  } finally {
    field.remove();
  }
}
