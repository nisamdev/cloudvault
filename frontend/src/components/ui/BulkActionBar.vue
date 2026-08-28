<script setup>
/**
 * Floating bar for multi-select actions on files / photos / folders.
 * Only mount this when something is selected — it is meant to appear and go.
 *
 * One row, always. Wrapping turned it into a ragged block the moment there
 * were more than three actions, so instead the actions scroll sideways and the
 * count stays put where it can be read.
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
  /** Which action is actually running, so only that one spins. */
  running: { type: String, default: "" },
});

const emit = defineEmits(["action", "clear"]);
</script>

<template>
  <div class="pointer-events-none fixed inset-x-0 bottom-4 z-30 flex justify-center px-4">
    <div
      class="pointer-events-auto flex max-w-[calc(100vw-2rem)] items-center gap-3 rounded-full border border-gray-200 bg-white py-2 pl-4 pr-2 shadow-lg"
      role="toolbar"
      :aria-label="`${count} ${noun}${count === 1 ? '' : 's'} selected`"
    >
      <p class="flex shrink-0 items-baseline gap-2 text-body-sm">
        <span class="font-semibold text-gray-800">{{ count }}</span>
        <span class="text-gray-500">{{ noun }}{{ count === 1 ? "" : "s" }}</span>
        <button
          type="button"
          class="font-medium text-primary-600 hover:underline"
          :disabled="busy"
          @click="emit('clear')"
        >
          Clear
        </button>
      </p>

      <span class="h-6 w-px shrink-0 bg-gray-200" aria-hidden="true"></span>

      <!-- Sideways rather than wrapping: a toolbar that reflows into three
           rows stops reading as a toolbar. -->
      <div class="flex items-center gap-1.5 overflow-x-auto">
        <button
          v-for="action in actions"
          :key="action.id"
          type="button"
          :disabled="busy || action.disabled"
          :title="action.label"
          :class="[
            'flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-3 py-1.5 text-body-sm font-medium transition disabled:opacity-50',
            action.danger
              ? 'text-error-600 hover:bg-error-50'
              : 'text-gray-700 hover:bg-gray-100',
          ]"
          @click="emit('action', action.id)"
        >
          <i
            :class="['fas', running === action.id ? 'fa-circle-notch fa-spin' : action.icon]"
            aria-hidden="true"
          ></i>
          {{ action.label }}
        </button>
      </div>
    </div>
  </div>
</template>
