<script setup>
import ScreenScaffold from "@/components/ui/ScreenScaffold.vue";
</script>

<template>
  <ScreenScaffold
    title="Photo Gallery"
    summary="Every photo in the family vault, newest first."
    reference="docs/PATTERNS.md §Image gallery"
    :todo="['Responsive tile grid with lazy-loaded thumbnails', 'Lightbox with keyboard navigation and focus trap', 'Date grouping (Today / Yesterday / Last week)', 'Image upload zone that auto-detects image MIME types']"
  />
</template>
