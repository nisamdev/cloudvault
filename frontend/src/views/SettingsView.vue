<script setup>
import ScreenScaffold from "@/components/ui/ScreenScaffold.vue";
</script>

<template>
  <ScreenScaffold
    title="Settings"
    summary="Account, security, storage and notification preferences."
    reference="docs/cloudvault_ui_prototype.html #settings-screen"
    :todo="['Account: name, email, avatar', 'Security: password change, 2FA, active sessions', 'Storage & plan: usage breakdown and quota', 'Privacy & notifications toggles']"
  />
</template>
