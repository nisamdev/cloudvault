<script setup>
import { onMounted, ref, watch } from "vue";
import { RouterLink, RouterView, useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import { useVaultStore } from "@/stores/vault";
import { formatFileSize } from "@/utils/formatting";
import AppDialog from "@/components/ui/AppDialog.vue";
import ToastStack from "@/components/ui/ToastStack.vue";
import VaultGate from "@/components/vault/VaultGate.vue";
import PrivateDestinationPicker from "@/components/vault/PrivateDestinationPicker.vue";

const router = useRouter();
const auth = useAuthStore();
const vault = useVaultStore();

// Mobile: the sidebar is an overlay. Tablet and up it is a static column
// (PATTERNS.md §Responsive).
const sidebarOpen = ref(false);

// Close the overlay after navigating, or it covers the page you just opened.
watch(() => router.currentRoute.value.fullPath, () => {
  sidebarOpen.value = false;
});

// So context menus know whether "Move to private" is available without visiting
// the Private screen first.
onMounted(() => {
  vault.refresh();
});

const navItems = [
  { name: "dashboard", label: "My Files", icon: "fa-folder" },
  { name: "recent", label: "Recent", icon: "fa-clock-rotate-left" },
  { name: "images", label: "Photos", icon: "fa-image" },
  { name: "shared", label: "Shared", icon: "fa-share-nodes" },
  { name: "household-register", label: "Register", icon: "fa-address-book" },
  { name: "private", label: "Private", icon: "fa-lock" },
  { name: "utilities", label: "Tools", icon: "fa-wand-magic-sparkles" },
  { name: "trash", label: "Trash", icon: "fa-trash" },
  { name: "settings", label: "Settings", icon: "fa-gear" },
];

async function handleLogout() {
  await auth.logout();
  router.push({ name: "login" });
}
</script>

<template>
  <!-- md:flex makes the sidebar and content sit side by side. Without it they
       are block elements and stack vertically. -->
  <div class="min-h-screen bg-gray-50 md:flex">
    <!-- ACCESSIBILITY.md: skip link must be the first focusable element. -->
    <a
      href="#main-content"
      class="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50 focus:rounded-base focus:bg-primary-600 focus:px-4 focus:py-2 focus:text-white"
    >
      Skip to main content
    </a>

    <!-- Scrim behind the mobile overlay -->
    <div
      v-if="sidebarOpen"
      class="fixed inset-0 z-30 bg-gray-900/50 md:hidden"
      aria-hidden="true"
      @click="sidebarOpen = false"
    ></div>

    <aside
      id="app-sidebar"
      :class="[
        'fixed inset-y-0 left-0 z-40 flex w-64 flex-col border-r border-gray-200 bg-white',
        'transition-transform duration-200 md:sticky md:top-0 md:h-screen md:shrink-0 md:translate-x-0',
        sidebarOpen ? 'translate-x-0' : '-translate-x-full',
      ]"
      aria-label="Main navigation"
    >
      <div class="flex h-16 shrink-0 items-center gap-2 border-b border-gray-200 px-6">
        <i class="fas fa-cloud text-xl text-primary-600" aria-hidden="true"></i>
        <span class="text-h4 font-bold text-gray-800">CloudVault</span>
      </div>

      <nav class="flex-1 space-y-1 overflow-y-auto p-4">
        <RouterLink
          v-for="item in navItems"
          :key="item.name"
          :to="{ name: item.name }"
          class="flex items-center gap-3 rounded-base px-4 py-2 text-body font-medium text-gray-600 transition hover:bg-gray-100 hover:text-gray-900"
          active-class="bg-primary-50 text-primary-700"
        >
          <i :class="['fas', item.icon, 'w-5 text-center']" aria-hidden="true"></i>
          {{ item.label }}
        </RouterLink>
      </nav>

      <!-- Storage meter (COMPONENTS.md §Sidebar) -->
      <div v-if="auth.user" class="shrink-0 border-t border-gray-200 p-4">
        <p class="mb-2 text-label font-medium text-gray-500">Storage</p>
        <div
          class="h-2 w-full overflow-hidden rounded-full bg-gray-200"
          role="progressbar"
          :aria-valuenow="Math.round(auth.user.storage_percent_used)"
          aria-valuemin="0"
          aria-valuemax="100"
          :aria-label="`${Math.round(auth.user.storage_percent_used)}% of storage used`"
        >
          <div
            class="h-full transition-all duration-300"
            :class="auth.user.storage_percent_used > 90 ? 'bg-error-500' : 'gradient-main'"
            :style="{ width: `${Math.min(auth.user.storage_percent_used, 100)}%` }"
          ></div>
        </div>
        <p class="mt-2 text-caption text-gray-500">
          {{ formatFileSize(auth.user.storage_used) }} of
          {{ formatFileSize(auth.user.storage_quota) }}
        </p>
      </div>
    </aside>

    <!-- min-w-0 lets long file names truncate instead of stretching the column -->
    <div class="flex min-w-0 flex-1 flex-col">
      <header
        class="sticky top-0 z-20 flex h-16 shrink-0 items-center gap-4 border-b border-gray-200 bg-white px-4 md:px-6"
      >
        <button
          type="button"
          class="rounded-md p-2 text-gray-600 hover:bg-gray-100 md:hidden"
          :aria-expanded="sidebarOpen"
          aria-controls="app-sidebar"
          aria-label="Toggle navigation menu"
          @click="sidebarOpen = !sidebarOpen"
        >
          <i class="fas fa-bars" aria-hidden="true"></i>
        </button>

        <span v-if="auth.family" class="truncate text-body font-medium text-gray-700">
          {{ auth.family.name }}
        </span>

        <div class="flex-1"></div>

        <span v-if="auth.user" class="hidden text-body-sm text-gray-600 sm:inline">
          {{ auth.user.full_name || auth.user.email }}
        </span>
        <button
          type="button"
          class="shrink-0 rounded-base px-3 py-2 text-body-sm font-medium text-gray-600 hover:bg-gray-100"
          @click="handleLogout"
        >
          <i class="fas fa-arrow-right-from-bracket mr-2" aria-hidden="true"></i>
          <span class="hidden sm:inline">Sign out</span>
        </button>
      </header>

      <main id="main-content" class="flex-1 p-4 md:p-6">
        <RouterView />
      </main>

      <!-- Mounted once for every screen inside the app shell. -->
      <AppDialog />
      <ToastStack />
      <VaultGate />
      <PrivateDestinationPicker />
    </div>
  </div>
</template>
