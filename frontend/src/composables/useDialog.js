import { ref } from "vue";

/**
 * Application dialogs, replacing window.confirm / window.prompt.
 *
 * Promise-based so call sites read the same way the native calls did:
 *
 *   if (!(await confirm({ message: "Delete?" }))) return;
 *   const name = await prompt({ label: "New name", value: file.name });
 *
 * State is module-level and a single <AppDialog /> renders it, so only one
 * dialog can ever be open — the same guarantee the native ones gave.
 */
const state = ref(null);
let resolver = null;

function open(config) {
  // A second dialog while one is open would strand the first promise.
  if (resolver) resolver(config.kind === "prompt" ? null : false);

  return new Promise((resolve) => {
    resolver = resolve;
    state.value = config;
  });
}

function settle(value) {
  const resolve = resolver;
  resolver = null;
  state.value = null;
  resolve?.(value);
}

export function useDialog() {
  return {
    state,

    /** @returns {Promise<boolean>} */
    confirm({ title = "Are you sure?", message = "", confirmLabel = "Confirm", cancelLabel = "Cancel", danger = false, detail = "" } = {}) {
      return open({ kind: "confirm", title, message, confirmLabel, cancelLabel, danger, detail });
    },

    /** @returns {Promise<string|null>} the trimmed value, or null if cancelled */
    prompt({ title = "", label = "", value = "", confirmLabel = "Save", cancelLabel = "Cancel", placeholder = "" } = {}) {
      return open({ kind: "prompt", title, label, value, confirmLabel, cancelLabel, placeholder });
    },

    resolve: settle,
  };
}
