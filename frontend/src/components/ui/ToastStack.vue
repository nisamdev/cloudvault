<script setup>
import { useToast } from "@/composables/useToast";

const { toasts, dismiss } = useToast();

const TONES = {
  success: { icon: "fa-circle-check", colour: "text-success-500" },
  error: { icon: "fa-triangle-exclamation", colour: "text-error-500" },
  info: { icon: "fa-circle-info", colour: "text-info-500" },
};

function run(toast) {
  toast.action?.();
  dismiss(toast.id);
}
</script>

<template>
  <!-- aria-live so a confirmation is announced, not only seen -->
  <div
    class="pointer-events-none fixed bottom-4 left-1/2 z-[70] flex w-full max-w-md -translate-x-1/2 flex-col gap-2 px-4"
    role="status"
    aria-live="polite"
  >
    <div
      v-for="toast in toasts"
      :key="toast.id"
      class="pointer-events-auto flex items-start gap-3 rounded-lg border border-gray-200 bg-white p-4 shadow-lg"
    >
      <i
        :class="['fas', TONES[toast.tone].icon, TONES[toast.tone].colour, 'mt-0.5']"
        aria-hidden="true"
      ></i>

      <div class="min-w-0 flex-1">
        <p class="text-body-sm font-medium text-gray-800">{{ toast.message }}</p>
        <p v-if="toast.detail" class="truncate text-caption text-gray-500">{{ toast.detail }}</p>
      </div>

      <button
        v-if="toast.action"
        type="button"
        class="shrink-0 text-body-sm font-semibold text-primary-600 hover:underline"
        @click="run(toast)"
      >
        {{ toast.actionLabel }}
      </button>

      <button
        type="button"
        class="shrink-0 rounded p-1 text-gray-400 hover:text-gray-600"
        aria-label="Dismiss"
        @click="dismiss(toast.id)"
      >
        <i class="fas fa-xmark text-caption" aria-hidden="true"></i>
      </button>
    </div>
  </div>
</template>
