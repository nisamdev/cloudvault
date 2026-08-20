import { ref } from "vue";

/**
 * Brief confirmations, with an optional action.
 *
 * Exists because "it worked" was invisible: after an upload or a signature the
 * screen looked the same and there was no way to tell where the file had gone.
 */
const toasts = ref([]);
let nextId = 1;

export function useToast() {
  function show({ message, detail = "", action = null, actionLabel = "", tone = "success", timeout = 6000 }) {
    const toast = { id: nextId++, message, detail, action, actionLabel, tone };
    toasts.value.push(toast);

    // A toast carrying an action stays until dismissed; otherwise it would
    // vanish before it could be used.
    if (!action && timeout) {
      setTimeout(() => dismiss(toast.id), timeout);
    }

    return toast.id;
  }

  function dismiss(id) {
    toasts.value = toasts.value.filter((t) => t.id !== id);
  }

  return { toasts, show, dismiss };
}
