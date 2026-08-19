<script setup>
import { nextTick, ref, watch } from "vue";
import { useDialog } from "@/composables/useDialog";

const { state, resolve } = useDialog();

const panel = ref(null);
const input = ref(null);
const confirmButton = ref(null);
const draft = ref("");
let previouslyFocused = null;

watch(state, async (config) => {
  if (!config) {
    previouslyFocused?.focus?.();
    return;
  }

  previouslyFocused = document.activeElement;
  draft.value = config.value ?? "";

  await nextTick();
  // A prompt wants the field ready to type in; a confirm should not have the
  // destructive button pre-armed under the Enter key of a stray keystroke, so
  // focus lands on the panel instead.
  if (config.kind === "prompt") {
    input.value?.focus();
    input.value?.select();
  } else {
    panel.value?.focus();
  }
});

function cancel() {
  resolve(state.value?.kind === "prompt" ? null : false);
}

function accept() {
  if (state.value?.kind === "prompt") {
    const value = draft.value.trim();
    resolve(value.length ? value : null);
  } else {
    resolve(true);
  }
}

function onKeydown(event) {
  if (event.key === "Escape") {
    event.preventDefault();
    cancel();
    return;
  }

  if (event.key !== "Tab") return;

  const focusable = panel.value?.querySelectorAll("button, input");
  if (!focusable?.length) return;

  const first = focusable[0];
  const last = focusable[focusable.length - 1];

  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
}
</script>

<template>
  <div
    v-if="state"
    class="fixed inset-0 z-[60] flex items-center justify-center bg-gray-900/50 p-4"
    @click.self="cancel"
  >
    <div
      ref="panel"
      role="dialog"
      aria-modal="true"
      tabindex="-1"
      aria-labelledby="app-dialog-title"
      :aria-describedby="state.message ? 'app-dialog-message' : undefined"
      class="w-full max-w-md rounded-xl bg-white shadow-2xl outline-none"
      @keydown="onKeydown"
    >
      <div class="p-6">
        <div class="flex items-start gap-4">
          <span
            v-if="state.danger"
            class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-error-50"
            aria-hidden="true"
          >
            <i class="fas fa-triangle-exclamation text-error-600"></i>
          </span>

          <div class="min-w-0 flex-1">
            <!-- Filenames have no natural break points, so they must be allowed
                 to break anywhere or they overflow the panel. -->
            <h2
              id="app-dialog-title"
              class="text-h3 font-semibold break-words text-gray-800 [overflow-wrap:anywhere]"
            >
              {{ state.title }}
            </h2>

            <p
              v-if="state.message"
              id="app-dialog-message"
              class="mt-2 text-body break-words text-gray-600 [overflow-wrap:anywhere]"
            >
              {{ state.message }}
            </p>

            <p v-if="state.detail" class="mt-2 text-body-sm text-gray-500">
              {{ state.detail }}
            </p>

            <form v-if="state.kind === 'prompt'" class="mt-4" @submit.prevent="accept">
              <label for="app-dialog-input" class="mb-2 block text-body-sm font-medium text-gray-700">
                {{ state.label }}
              </label>
              <input
                id="app-dialog-input"
                ref="input"
                v-model="draft"
                type="text"
                :placeholder="state.placeholder"
                class="w-full rounded-base border border-gray-300 px-3 py-2 outline-none focus:border-transparent focus:ring-2 focus:ring-primary-500"
              />
            </form>
          </div>
        </div>
      </div>

      <footer class="flex justify-end gap-3 rounded-b-xl bg-gray-50 px-6 py-4">
        <button
          type="button"
          class="rounded-base border border-gray-300 bg-white px-4 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
          @click="cancel"
        >
          {{ state.cancelLabel }}
        </button>
        <button
          ref="confirmButton"
          type="button"
          :disabled="state.kind === 'prompt' && !draft.trim()"
          :class="[
            'rounded-base px-4 py-2 text-body-sm font-semibold text-white transition disabled:cursor-not-allowed disabled:opacity-50',
            state.danger ? 'bg-error-600 hover:bg-error-500' : 'gradient-main hover:opacity-95',
          ]"
          @click="accept"
        >
          {{ state.confirmLabel }}
        </button>
      </footer>
    </div>
  </div>
</template>
