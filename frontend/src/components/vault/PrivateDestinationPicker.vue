<script setup>
import { ref } from "vue";
import { usePrivateDestination } from "@/composables/usePrivateDestination";

/**
 * Asks where inside Private something should go. Mounted once in AppLayout;
 * screens open it through usePrivateDestination().pick().
 */
const {
  open,
  title,
  allowRoot,
  destinations,
  loading,
  error,
  choose,
  chooseRoot,
  cancel,
  createAndChoose,
} = usePrivateDestination();

const newName = ref("");
const showCreate = ref(false);

function submitCreate() {
  createAndChoose(newName.value);
  newName.value = "";
  showCreate.value = false;
}

function onCancel() {
  newName.value = "";
  showCreate.value = false;
  cancel();
}
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-end justify-center bg-gray-900/40 p-4 sm:items-center"
    role="dialog"
    aria-modal="true"
    aria-labelledby="private-dest-title"
    @click.self="onCancel"
  >
    <div class="flex max-h-[85vh] w-full max-w-md flex-col overflow-hidden rounded-lg bg-white shadow-lg">
      <div class="border-b border-gray-200 px-4 py-3">
        <h2 id="private-dest-title" class="text-body font-semibold text-gray-800">
          {{ title }}
        </h2>
        <p class="mt-0.5 text-caption text-gray-500">Choose a folder in Private</p>
      </div>

      <p
        v-if="error"
        role="alert"
        class="mx-4 mt-3 rounded-base bg-error-50 px-3 py-2 text-caption text-error-600"
      >
        {{ error }}
      </p>

      <div v-if="loading" class="space-y-2 p-4">
        <div v-for="n in 3" :key="n" class="h-10 animate-pulse rounded-base bg-gray-100"></div>
      </div>

      <ul v-else class="max-h-72 flex-1 overflow-y-auto p-2">
        <li v-if="allowRoot">
          <button
            type="button"
            class="flex w-full items-center gap-3 rounded-base px-3 py-2.5 text-left text-body-sm hover:bg-primary-50"
            @click="chooseRoot()"
          >
            <i class="fas fa-house text-gray-400" aria-hidden="true"></i>
            <span>
              <span class="block font-medium text-gray-800">Top level</span>
              <span class="block text-caption text-gray-500">Not inside another folder</span>
            </span>
          </button>
        </li>

        <li v-for="item in destinations" :key="item.folder.id">
          <button
            type="button"
            class="flex w-full items-center gap-3 rounded-base px-3 py-2.5 text-left text-body-sm hover:bg-primary-50"
            @click="choose(item.folder.id)"
          >
            <i class="fas fa-folder text-warning-500" aria-hidden="true"></i>
            <span class="truncate text-gray-800">{{ item.path }}</span>
          </button>
        </li>

        <li
          v-if="!destinations.length && !allowRoot"
          class="px-3 py-6 text-center text-body-sm text-gray-500"
        >
          No private folders yet — create one below.
        </li>
      </ul>

      <div class="border-t border-gray-200 p-3">
        <div v-if="showCreate" class="flex gap-2">
          <input
            v-model="newName"
            type="text"
            class="min-w-0 flex-1 rounded-base border border-gray-300 px-3 py-2 text-body-sm focus:border-primary-500 focus:outline-none focus:ring-1 focus:ring-primary-500"
            placeholder="Folder name"
            aria-label="New private folder name"
            @keydown.enter.prevent="submitCreate"
          />
          <button
            type="button"
            class="rounded-base gradient-main px-3 py-2 text-body-sm font-semibold text-white"
            @click="submitCreate"
          >
            Create
          </button>
        </div>
        <button
          v-else
          type="button"
          class="w-full rounded-base border border-dashed border-gray-300 px-3 py-2 text-body-sm font-medium text-gray-700 transition hover:border-primary-400 hover:bg-primary-50"
          @click="showCreate = true"
        >
          <i class="fas fa-folder-plus mr-1.5" aria-hidden="true"></i>New private folder
        </button>
      </div>

      <div class="border-t border-gray-200 px-4 py-3 text-right">
        <button
          type="button"
          class="rounded-base px-3 py-1.5 text-body-sm font-medium text-gray-600 hover:bg-gray-50"
          @click="onCancel"
        >
          Cancel
        </button>
      </div>
    </div>
  </div>
</template>
