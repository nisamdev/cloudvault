<script setup>
import { RouterView } from "vue-router";
</script>

<template>
  <!-- Routes own their own chrome: auth screens are full-bleed, app screens
       render inside AppLayout. -->
  <RouterView />
</template>
