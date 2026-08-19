<script setup>
import ScreenScaffold from "@/components/ui/ScreenScaffold.vue";
</script>

<template>
  <ScreenScaffold
    title="Shared"
    summary="Files shared with the family and via public links."
    reference="docs/PATTERNS.md §Sharing"
    :todo="['Shared-with-me and shared-by-me tabs', 'Public link management: expiry, password, revoke', 'Role badges (owner / editor / viewer)']"
  />
</template>
