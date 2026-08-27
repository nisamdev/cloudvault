<script setup>
/**
 * Register › Add › Person — one quiet trail, not three back buttons and headings.
 */
defineProps({
  crumbs: {
    type: Array,
    required: true,
    // { label: string, to?: RouteLocationRaw }
  },
});
</script>

<template>
  <nav aria-label="Breadcrumb" class="mb-5">
    <ol class="flex flex-wrap items-center gap-x-1.5 text-body-sm text-gray-500">
      <li v-for="(crumb, index) in crumbs" :key="index" class="flex items-center gap-x-1.5">
        <span v-if="index > 0" aria-hidden="true" class="text-gray-300">/</span>
        <RouterLink
          v-if="crumb.to"
          :to="crumb.to"
          class="transition hover:text-primary-600"
        >
          {{ crumb.label }}
        </RouterLink>
        <span v-else class="font-medium text-gray-800">{{ crumb.label }}</span>
      </li>
    </ol>
  </nav>
</template>
