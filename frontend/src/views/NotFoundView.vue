<script setup>
import { RouterLink } from "vue-router";
</script>

<template>
  <div class="flex min-h-screen flex-col items-center justify-center bg-gray-50 p-4 text-center">
    <i class="fas fa-cloud text-5xl text-gray-300" aria-hidden="true"></i>
    <h1 class="mt-6 text-h1 font-bold text-gray-800">Page not found</h1>
    <p class="mt-2 text-body text-gray-600">
      That link may be broken, or the file may have been moved.
    </p>
    <RouterLink
      :to="{ name: 'dashboard' }"
      class="mt-6 rounded-base bg-gradient-to-r from-primary-600 to-secondary-600 px-6 py-2 font-semibold text-white"
    >
      Back to my files
    </RouterLink>
  </div>
</template>
