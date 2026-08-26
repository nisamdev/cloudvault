<script setup>
/**
 * Floating bar for multi-select actions on files / photos / folders.
 * Only mount this when something is selected — it is meant to appear and go.
 */
defineProps({
  count: { type: Number, required: true },
  noun: { type: String, default: "item" },
  actions: {
    type: Array,
    default: () => [],
    // { id, label, icon, danger?, disabled? }
  },
  busy: { type: Boolean, default: false },
});

const emit = defineEmits(["action", "clear"]);
</script>

<template>
  <div
    class="pointer-events-none fixed inset-x-0 bottom-4 z-30 flex justify-center px-4"
  >
    <div
      class="pointer-events-auto flex max-w-3xl flex-wrap items-center justify-between gap-3 rounded-lg border border-gray-200 bg-white px-4 py-3 shadow-lg"
      role="toolbar"
      :aria-label="`${count} ${noun}${count === 1 ? '' : 's'} selected`"
    >
      <p class="text-body-sm font-medium text-gray-800">
        {{ count }} {{ noun }}{{ count === 1 ? "" : "s" }} selected
        <button
          type="button"
          class="ml-2 text-primary-600 hover:underline"
          :disabled="busy"
          @click="emit('clear')"
        >
          Clear
        </button>
      </p>

      <div class="flex flex-wrap items-center gap-2">
        <button
          v-for="action in actions"
          :key="action.id"
          type="button"
          :disabled="busy || action.disabled"
          :class="[
            'rounded-base border px-3 py-1.5 text-body-sm font-medium transition disabled:opacity-50',
            action.danger
              ? 'border-error-200 text-error-600 hover:bg-error-50'
              : 'border-gray-300 text-gray-700 hover:bg-gray-50',
          ]"
          @click="emit('action', action.id)"
        >
          <i
            :class="['fas mr-1.5', busy ? 'fa-circle-notch fa-spin' : action.icon]"
            aria-hidden="true"
          ></i>
          {{ action.label }}
        </button>
      </div>
    </div>
  </div>
</template>
