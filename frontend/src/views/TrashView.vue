<script setup>
import { computed, onMounted, ref } from "vue";
import { useFilesStore } from "@/stores/files";
import { useLibraryStore } from "@/stores/library";
import { formatFileSize, fileIcon } from "@/utils/formatting";

const filesStore = useFilesStore();
const library = useLibraryStore();

const busy = ref(false);
const error = ref("");

const retentionDays = 30;

const isEmpty = computed(
  () => !filesStore.loading && filesStore.items.length === 0 && library.trashedFolders.length === 0,
);

const reclaimable = computed(() => filesStore.items.reduce((sum, f) => sum + (f.size ?? 0), 0));

onMounted(load);

function load() {
  error.value = "";
  filesStore.fetchFiles({ trashed: true });
  library.fetchTrashedFolders().catch((e) => (error.value = e.userMessage));
}

/** Days until CloudVault removes it automatically. */
function daysLeft(item) {
  if (!item.purge_after) return null;

  const ms = new Date(item.purge_after) - Date.now();
  return Math.max(Math.ceil(ms / 86_400_000), 0);
}

function countdownLabel(item) {
  const days = daysLeft(item);
  if (days === null) return "";
  if (days === 0) return "Deletes today";
  return `Deletes in ${days} ${days === 1 ? "day" : "days"}`;
}

async function restoreFile(file) {
  try {
    await filesStore.restore(file);
  } catch (e) {
    error.value = e.userMessage;
  }
}

async function restoreFolder(folder) {
  try {
    await library.restoreFolder(folder);
    load();
  } catch (e) {
    error.value = e.userMessage;
  }
}

async function purgeFile(file) {
  if (!window.confirm(`Permanently delete "${file.name}"? This cannot be undone.`)) return;

  try {
    await filesStore.purge(file);
  } catch (e) {
    error.value = e.userMessage;
  }
}

async function emptyTrash() {
  const count = filesStore.items.length;
  if (!count) return;
  if (!window.confirm(`Permanently delete ${count} ${count === 1 ? "item" : "items"}? This cannot be undone.`)) return;

  busy.value = true;
  error.value = "";

  // Sequential rather than parallel: each purge adjusts the same storage
  // counters, and a burst of them would fight over the same rows.
  for (const file of [...filesStore.items]) {
    try {
      await filesStore.purge(file);
    } catch (e) {
      error.value = e.userMessage;
      break;
    }
  }

  busy.value = false;
  load();
}
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-center justify-between gap-4">
      <div>
        <h1 class="text-h2 font-bold text-gray-800">Trash</h1>
        <p class="mt-1 text-body-sm text-gray-500">
          Items are deleted automatically after {{ retentionDays }} days.
          <template v-if="reclaimable > 0">
            {{ formatFileSize(reclaimable) }} can be reclaimed.
          </template>
        </p>
      </div>

      <button
        v-if="filesStore.items.length"
        type="button"
        :disabled="busy"
        class="rounded-base border border-error-500 px-4 py-2 text-body-sm font-semibold text-error-600 transition hover:bg-error-50 disabled:opacity-60"
        @click="emptyTrash"
      >
        <i class="fas fa-trash mr-2" aria-hidden="true"></i>
        {{ busy ? "Emptying…" : "Empty trash" }}
      </button>
    </header>

    <p
      v-if="error"
      role="alert"
      class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
    >
      {{ error }}
    </p>

    <div v-if="filesStore.loading" class="space-y-2">
      <div v-for="n in 3" :key="n" class="h-16 animate-pulse rounded-lg bg-gray-100"></div>
    </div>

    <div v-else-if="isEmpty" class="rounded-lg border border-gray-200 bg-white p-12 text-center">
      <i class="fas fa-trash-can text-4xl text-gray-300" aria-hidden="true"></i>
      <h2 class="mt-4 text-h3 font-semibold text-gray-800">Trash is empty</h2>
      <p class="mt-2 text-body text-gray-500">Deleted files and folders show up here first.</p>
    </div>

    <ul v-else class="space-y-2">
      <!-- Folders first, matching the main listing -->
      <li
        v-for="folder in library.trashedFolders"
        :key="`folder-${folder.id}`"
        class="flex items-center gap-4 rounded-lg border border-gray-200 bg-white p-4"
      >
        <i class="fas fa-folder text-xl text-warning-500" aria-hidden="true"></i>

        <div class="min-w-0 flex-1">
          <p class="truncate text-body font-medium text-gray-800">{{ folder.name }}</p>
          <p class="text-caption text-gray-500">
            Folder · {{ folder.file_count }} {{ folder.file_count === 1 ? "file" : "files" }}
            <span v-if="countdownLabel(folder)"> · {{ countdownLabel(folder) }}</span>
          </p>
        </div>

        <button
          type="button"
          class="rounded-base border border-gray-300 px-3 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
          @click="restoreFolder(folder)"
        >
          <i class="fas fa-rotate-left mr-2" aria-hidden="true"></i>Restore
        </button>
      </li>

      <li
        v-for="file in filesStore.items"
        :key="file.id"
        class="flex items-center gap-4 rounded-lg border border-gray-200 bg-white p-4"
      >
        <i :class="['fas', fileIcon(file).icon, fileIcon(file).className, 'text-xl']" aria-hidden="true"></i>

        <div class="min-w-0 flex-1">
          <p class="truncate text-body font-medium text-gray-800">{{ file.name }}</p>
          <p class="text-caption text-gray-500">
            {{ formatFileSize(file.size) }}
            <span v-if="countdownLabel(file)">
              ·
              <span :class="daysLeft(file) <= 3 ? 'font-medium text-error-600' : ''">
                {{ countdownLabel(file) }}
              </span>
            </span>
            · {{ file.owner.name }}
          </p>
        </div>

        <div class="flex items-center gap-2">
          <button
            type="button"
            class="rounded-base border border-gray-300 px-3 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
            :aria-label="`Restore ${file.name}`"
            @click="restoreFile(file)"
          >
            <i class="fas fa-rotate-left mr-2" aria-hidden="true"></i>Restore
          </button>
          <button
            v-if="file.permissions.can_delete"
            type="button"
            class="rounded-md p-2 text-gray-500 transition hover:bg-error-50 hover:text-error-600"
            :aria-label="`Permanently delete ${file.name}`"
            @click="purgeFile(file)"
          >
            <i class="fas fa-xmark" aria-hidden="true"></i>
          </button>
        </div>
      </li>
    </ul>
  </section>
</template>
