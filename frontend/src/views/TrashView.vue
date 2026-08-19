<script setup>
import ScreenScaffold from "@/components/ui/ScreenScaffold.vue";
</script>

<template>
  <ScreenScaffold
    title="Trash"
    summary="Deleted items, recoverable for 30 days."
    reference="docs/PATTERNS.md §Modals & Dialogs"
    :todo="['Restore and permanently-delete actions', 'Auto-purge countdown per item', 'Empty-trash confirmation dialog']"
  />
</template>
