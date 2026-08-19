<script setup>
/**
 * Placeholder for a screen that is routed and styled but not yet implemented.
 * It states plainly what still has to be built, so a running app is never
 * mistaken for a finished one.
 */
defineProps({
  title: { type: String, required: true },
  summary: { type: String, required: true },
  todo: { type: Array, default: () => [] },
  reference: { type: String, default: "" },
});
</script>

<template>
  <section class="mx-auto max-w-3xl">
    <h1 class="text-h2 font-bold text-gray-800">{{ title }}</h1>
    <p class="mt-2 text-body text-gray-600">{{ summary }}</p>

    <div class="mt-6 rounded-lg border border-dashed border-gray-300 bg-white p-6">
      <p class="flex items-center gap-2 text-label uppercase tracking-wide text-gray-500">
        <i class="fas fa-hammer" aria-hidden="true"></i>
        Not implemented yet
      </p>
      <ul class="mt-4 space-y-2">
        <li
          v-for="item in todo"
          :key="item"
          class="flex items-start gap-3 text-body text-gray-700"
        >
          <i class="fas fa-square-check mt-1 text-gray-300" aria-hidden="true"></i>
          <span>{{ item }}</span>
        </li>
      </ul>
      <p v-if="reference" class="mt-4 text-caption text-gray-500">
        Spec: {{ reference }}
      </p>
    </div>
  </section>
</template>
