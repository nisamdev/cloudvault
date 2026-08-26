<script setup>
import { computed, onMounted, ref } from "vue";
import api from "@/api/client";
import { useFilesStore } from "@/stores/files";
import { useLibraryStore } from "@/stores/library";
import { useDialog } from "@/composables/useDialog";
import { formatFileSize, fileIcon } from "@/utils/formatting";

const filesStore = useFilesStore();
const library = useLibraryStore();
const dialog = useDialog();

const busy = ref(false);
const error = ref("");

const retentionDays = 30;

const isEmpty = computed(
  () => !filesStore.loading && filesStore.items.length === 0 && library.trashedFolders.length === 0,
);

const reclaimable = computed(() => filesStore.items.reduce((sum, f) => sum + (f.size ?? 0), 0));

onMounted(load);

async function load() {
  error.value = "";
  try {
    await Promise.all([
      filesStore.fetchFiles({ trashed: true }),
      library.fetchTrashedFolders(),
    ]);
  } catch (e) {
    error.value = e.userMessage;
  }
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
  const ok = await dialog.confirm({
    title: `Restore "${file.name}"?`,
    message: file.locked
      ? "It goes back into your Private section."
      : "It goes back to My Files.",
    // A file whose folder is gone reappears at the top level, so say so rather
    // than letting the user hunt for it.
    detail: file.folder || file.locked ? undefined : "It will appear at the top level.",
    confirmLabel: "Restore",
  });
  if (!ok) return;

  try {
    await filesStore.restore(file);
  } catch (e) {
    error.value = e.userMessage;
  }
}

async function restoreFolder(folder) {
  const ok = await dialog.confirm({
    title: `Restore "${folder.name}"?`,
    message: folder.file_count
      ? `The folder and its ${folder.file_count} ${folder.file_count === 1 ? "file" : "files"} come back.`
      : "The folder comes back.",
    detail: "If its parent folder is still in the trash, it returns to the top level.",
    confirmLabel: "Restore",
  });
  if (!ok) return;

  try {
    await library.restoreFolder(folder);
    load();
  } catch (e) {
    error.value = e.userMessage;
  }
}

async function purgeFile(file) {
  const ok = await dialog.confirm({
    title: `Permanently delete "${file.name}"?`,
    message: "This cannot be undone.",
    detail: `${formatFileSize(file.size)} will be returned to your storage.`,
    confirmLabel: "Delete forever",
    danger: true,
  });
  if (!ok) return;

  try {
    await filesStore.purge(file);
  } catch (e) {
    error.value = e.userMessage;
  }
}

async function emptyTrash() {
  const fileCount = filesStore.totalCount || filesStore.items.length;
  const folderCount = library.trashedFolders.length;
  const total = fileCount + folderCount;
  if (!total) return;

  const ok = await dialog.confirm({
    title: "Empty the trash?",
    message: `${total} ${total === 1 ? "item" : "items"} will be permanently deleted. This cannot be undone.`,
    detail: reclaimable.value > 0 ? `${formatFileSize(reclaimable.value)} will be returned to your storage.` : undefined,
    confirmLabel: "Delete everything",
    danger: true,
  });
  if (!ok) return;

  busy.value = true;
  error.value = "";

  try {
    // One API call — emptying page-by-page left the rest of the bin looking
    // like it had come back after a reload.
    await api.delete("/trash");
    await load();
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    busy.value = false;
  }
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
        v-if="filesStore.items.length || library.trashedFolders.length"
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
          <p class="truncate text-body font-medium text-gray-800">
            {{ file.name }}
            <span
              v-if="file.locked"
              class="ml-2 inline-flex items-center gap-1 text-caption font-normal text-gray-500"
            >
              <i class="fas fa-lock text-[10px]" aria-hidden="true"></i>Private
            </span>
          </p>
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
