<script setup>
import { computed } from "vue";
import { useAuthStore } from "@/stores/auth";

/**
 * Why the family's shelves are bare.
 *
 * Somebody shut out of the family vault is still in the family: it stays in
 * their sidebar, they can still switch to it, and every view of it is empty.
 * Empty and unexplained is the worst of the two — it reads as a broken app
 * rather than as a decision somebody made.
 */
const auth = useAuthStore();

const shutOut = computed(() => auth.family && auth.family.can_use_vault === false);
</script>

<template>
  <div
    v-if="shutOut"
    class="mb-6 flex flex-wrap items-center gap-3 rounded-xl border border-warning-100 bg-warning-50 px-5 py-4"
  >
    <i class="fas fa-lock text-warning-600" aria-hidden="true"></i>
    <div class="min-w-0 flex-1">
      <p class="text-body font-medium text-gray-800">
        {{ auth.family.name }} isn't open to you at the moment
      </p>
      <p class="mt-0.5 text-body-sm text-gray-600">
        Someone who runs the family has turned off your access to what it shares. Your own files,
        records and private section are untouched — ask them to turn it back on.
      </p>
    </div>
  </div>
</template>
