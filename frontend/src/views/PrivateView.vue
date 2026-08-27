<script setup>
import { computed, onMounted, ref, watch } from "vue";
import api from "@/api/client";
import { useFilesStore } from "@/stores/files";
import { useLibraryStore } from "@/stores/library";
import { useVaultStore } from "@/stores/vault";
import { useDialog } from "@/composables/useDialog";
import { useToast } from "@/composables/useToast";
import FilePreview from "@/components/files/FilePreview.vue";
import UploadZone from "@/components/files/UploadZone.vue";
import { useVaultGate } from "@/composables/useVaultGate";
import { formatFileSize, formatRelativeDate, fileIcon } from "@/utils/formatting";

/**
 * The private section — browse folders and files that are encrypted at rest.
 *
 * Bringing things in from My Files / Photos is done there (Move to Private),
 * not duplicated here.
 */
const filesStore = useFilesStore();
const library = useLibraryStore();
const vault = useVaultStore();
const dialog = useDialog();
const toast = useToast();
const vaultGate = useVaultGate();

const error = ref("");
const busy = ref("");
const previewFile = ref(null);
const loading = ref(false);

/** null = top level of the private tree. */
const currentFolderId = ref(null);
const breadcrumbs = ref([]);
const lockedFolders = ref([]);

/**
 * What is behind the lock, counting only the kinds that are actually there —
 * "0 files, 0 folders" over a section holding six records was simply untrue.
 */
const lockedSummary = computed(() => {
  const parts = [
    [vault.lockedRecords, "record"],
    [vault.lockedFiles, "file"],
    [vault.lockedFolders, "folder"],
  ]
    .filter(([count]) => count > 0)
    .map(([count, noun]) => `${count} ${noun}${count === 1 ? "" : "s"}`);

  return parts.length ? parts.join(", ") : "Nothing in here yet";
});

const lockedIds = computed(() => new Set(lockedFolders.value.map((f) => f.id)));

const visibleFolders = computed(() => {
  const list = lockedFolders.value;
  if (currentFolderId.value == null) {
    return list
      .filter((f) => !f.parent_id || !lockedIds.value.has(f.parent_id))
      .sort((a, b) => a.name.localeCompare(b.name));
  }
  return list
    .filter((f) => f.parent_id === currentFolderId.value)
    .sort((a, b) => a.name.localeCompare(b.name));
});

const allFiles = computed(() =>
  [...filesStore.items].sort((a, b) => a.name.localeCompare(b.name)),
);

const currentFolder = computed(
  () => lockedFolders.value.find((f) => f.id === currentFolderId.value) ?? null,
);

const moveDestinations = computed(() =>
  lockedFolders.value
    .map((folder) => ({ folder, path: folderPath(folder) }))
    .sort((a, b) => a.path.localeCompare(b.path)),
);

const movePicker = ref(null);

onMounted(async () => {
  await vault.refresh();
  if (vault.unlocked) await load();
});

watch(
  () => vault.unlocked,
  (open) => {
    if (open) {
      load();
    } else {
      filesStore.items = [];
      lockedFolders.value = [];
      currentFolderId.value = null;
      breadcrumbs.value = [];
    }
  },
);

async function load() {
  error.value = "";
  loading.value = true;
  try {
    const folderId = currentFolderId.value;
    const [, folders] = await Promise.all([
      filesStore.fetchFiles({
        filters: { locked: "true" },
        folderId: folderId ?? "",
        fileType: null,
      }),
      api.get("/folders", { params: { locked: "true" } }),
    ]);

    lockedFolders.value = folders.data.folders;

    if (folderId != null && !lockedFolders.value.some((f) => f.id === folderId)) {
      currentFolderId.value = null;
      breadcrumbs.value = [];
      await load();
    }
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}

function folderPath(folder) {
  const parts = [folder.name];
  let parentId = folder.parent_id;
  const seen = new Set([folder.id]);
  while (parentId && lockedIds.value.has(parentId) && !seen.has(parentId)) {
    seen.add(parentId);
    const parent = lockedFolders.value.find((f) => f.id === parentId);
    if (!parent) break;
    parts.unshift(parent.name);
    parentId = parent.parent_id;
  }
  return parts.join(" / ");
}

function descendantLockedIds(folderId) {
  const out = [];
  let queue = lockedFolders.value.filter((f) => f.parent_id === folderId).map((f) => f.id);
  while (queue.length) {
    out.push(...queue);
    queue = lockedFolders.value.filter((f) => queue.includes(f.parent_id)).map((f) => f.id);
  }
  return out;
}

function unlock() {
  vaultGate.open(vault.exists ? "unlock" : "setup");
}

async function lockUp() {
  await vault.lock();
  filesStore.items = [];
  lockedFolders.value = [];
  currentFolderId.value = null;
  breadcrumbs.value = [];
}

async function openFolder(folderId) {
  currentFolderId.value = folderId;
  if (folderId == null) {
    breadcrumbs.value = [];
    await load();
    return;
  }

  await load();

  try {
    const { data } = await api.get(`/folders/${folderId}`);
    const trail = [...data.breadcrumbs, { id: data.folder.id, name: data.folder.name }];
    breadcrumbs.value = trail.filter(
      (crumb) => lockedIds.value.has(crumb.id) || crumb.id === folderId,
    );
  } catch {
    breadcrumbs.value = currentFolder.value
      ? [{ id: currentFolder.value.id, name: currentFolder.value.name }]
      : [];
  }
}

async function createPrivateFolder() {
  const parent = currentFolder.value;
  const name = await dialog.prompt({
    title: parent ? `New folder inside "${parent.name}"` : "New folder",
    label: "Folder name",
    placeholder: "e.g. Tax docs",
    confirmLabel: "Create",
  });
  if (!name?.trim()) return;

  busy.value = "create-folder";
  try {
    const folder = await library.createFolder({
      name: name.trim(),
      parentId: parent?.id ?? null,
      locked: true,
    });
    toast.show({ message: "Folder created", detail: folder.name });
    await load();
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    busy.value = "";
  }
}

async function renameFolder(folder) {
  const name = await dialog.prompt({
    title: "Rename folder",
    label: "Folder name",
    value: folder.name,
    confirmLabel: "Rename",
  });
  if (!name?.trim() || name.trim() === folder.name) return;

  busy.value = `rename-${folder.id}`;
  try {
    await library.renameFolder(folder, name.trim());
    toast.show({ message: "Folder renamed", detail: name.trim() });
    await load();
    if (currentFolderId.value === folder.id) {
      breadcrumbs.value = breadcrumbs.value.map((c) =>
        c.id === folder.id ? { ...c, name: name.trim() } : c,
      );
    }
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    busy.value = "";
  }
}

async function unlockFolder(folder) {
  const ok = await dialog.confirm({
    title: `Move "${folder.name}" back to My Files?`,
    message: "Everything inside is decrypted and leaves this section.",
    confirmLabel: "Move to My Files",
  });
  if (!ok) return;

  busy.value = `unlock-${folder.id}`;
  try {
    const { data } = await api.delete(`/folders/${folder.id}/lock`);
    toast.show({
      message: `${folder.name} is in My Files again`,
      detail: `${data.files} file${data.files === 1 ? "" : "s"}`,
    });
    if (currentFolderId.value === folder.id) {
      currentFolderId.value = null;
      breadcrumbs.value = [];
    }
    await load();
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    busy.value = "";
  }
}

async function trashFolder(folder) {
  const ok = await dialog.confirm({
    title: `Move "${folder.name}" to trash?`,
    message: "The folder and everything in it go to Trash for 30 days.",
    confirmLabel: "Move to trash",
    danger: true,
  });
  if (!ok) return;

  busy.value = `trash-folder-${folder.id}`;
  try {
    await library.deleteFolder(folder);
    toast.show({ message: `Moved ${folder.name} to trash` });
    if (currentFolderId.value === folder.id) {
      currentFolderId.value = null;
      breadcrumbs.value = [];
    }
    await load();
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    busy.value = "";
  }
}

async function takeOut(file) {
  const ok = await dialog.confirm({
    title: `Move "${file.name}" to My Files?`,
    message: "It is decrypted and leaves this section.",
    confirmLabel: "Move to My Files",
  });
  if (!ok) return;

  busy.value = `out-${file.id}`;
  try {
    await filesStore.removeFromPrivate(file);
    toast.show({ message: "Moved to My Files", detail: file.name });
    await vault.refresh();
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    busy.value = "";
  }
}

async function trashFile(file) {
  const ok = await dialog.confirm({
    title: `Move "${file.name}" to trash?`,
    message: "You can restore it from Trash for 30 days.",
    confirmLabel: "Move to trash",
    danger: true,
  });
  if (!ok) return;

  busy.value = `trash-${file.id}`;
  try {
    await filesStore.trash(file);
    toast.show({ message: "Moved to trash", detail: file.name });
    await vault.refresh();
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    busy.value = "";
  }
}

function openMoveFile(file) {
  movePicker.value = {
    kind: "file",
    item: file,
    excludeIds: new Set([file.folder_id].filter(Boolean)),
  };
}

function openMoveFolder(folder) {
  const exclude = new Set([folder.id, ...descendantLockedIds(folder.id)]);
  movePicker.value = { kind: "folder", item: folder, excludeIds: exclude };
}

async function confirmMove(destinationId) {
  const picker = movePicker.value;
  if (!picker) return;

  const destId = destinationId === "" ? null : destinationId;
  movePicker.value = null;

  if (picker.kind === "file") {
    if (destId == null) {
      error.value = "Pick a folder for that file.";
      return;
    }
    if (picker.item.folder_id === destId) return;

    busy.value = `move-${picker.item.id}`;
    try {
      await filesStore.move(picker.item, destId);
      toast.show({
        message: "Moved",
        detail: moveDestinations.value.find((d) => d.folder.id === destId)?.path,
      });
      await load();
    } catch (e) {
      error.value = e.userMessage;
    } finally {
      busy.value = "";
    }
    return;
  }

  if (picker.item.parent_id === destId) return;
  if (destId != null && picker.excludeIds.has(destId)) return;

  busy.value = `move-folder-${picker.item.id}`;
  try {
    await library.moveFolder(picker.item, destId);
    toast.show({ message: "Folder moved", detail: picker.item.name });
    await load();
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    busy.value = "";
  }
}

async function download(file) {
  try {
    const response = await api.get(`/files/${file.id}/content`, {
      params: { disposition: "attachment" },
      responseType: "blob",
      timeout: 120_000,
    });

    const url = URL.createObjectURL(response.data);
    const link = document.createElement("a");
    link.href = url;
    link.download = file.name;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 10_000);
  } catch (e) {
    error.value = e.userMessage;
  }
}

async function onUploadComplete({ uploaded, failed }) {
  await load();
  await vault.refresh();
  if (!uploaded.length) {
    if (failed) toast.show({ message: "Upload failed", tone: "error" });
    return;
  }
  toast.show({
    message: uploaded.length === 1 ? "Uploaded" : `Uploaded ${uploaded.length} files`,
    detail: failed ? `${failed} failed` : (uploaded[0]?.name ?? ""),
  });
}
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-start justify-between gap-4">
      <div>
        <h1 class="text-h2 font-bold text-gray-800">
          <i class="fas fa-lock mr-2 text-gray-400" aria-hidden="true"></i>Private
        </h1>
        <p class="mt-1 text-body-sm text-gray-500">
          Encrypted with your passphrase. Add items from My Files or Photos.
        </p>
      </div>

      <button
        v-if="vault.unlocked"
        type="button"
        class="rounded-base border border-gray-300 px-4 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
        @click="lockUp"
      >
        <i class="fas fa-lock mr-2" aria-hidden="true"></i>Lock
      </button>
    </header>

    <p v-if="error" role="alert" class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
      {{ error }}
    </p>

    <!-- Closed -->
    <div v-if="!vault.unlocked" class="rounded-lg border border-gray-200 bg-white p-12 text-center">
      <i class="fas fa-shield-halved text-5xl text-gray-300" aria-hidden="true"></i>

      <template v-if="vault.exists">
        <h2 class="mt-4 text-h3 font-semibold text-gray-800">Locked</h2>
        <p class="mx-auto mt-2 max-w-md text-body text-gray-500">
          {{ lockedSummary }}. Enter your passphrase to open.
        </p>
      </template>
      <template v-else>
        <h2 class="mt-4 text-h3 font-semibold text-gray-800">Set up Private</h2>
        <p class="mx-auto mt-2 max-w-md text-body text-gray-500">
          Choose a passphrase. Files you put here stay encrypted until you unlock.
        </p>
      </template>

      <button
        type="button"
        class="mt-6 rounded-base gradient-main px-6 py-2.5 font-semibold text-white"
        @click="unlock"
      >
        {{ vault.exists ? "Unlock" : "Set it up" }}
      </button>
    </div>

    <!-- Open -->
    <template v-else>
      <p class="mb-4 text-caption text-gray-500">
        Unlocked for this tab · locks when you leave or after 20 minutes idle
      </p>

      <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
        <nav
          v-if="breadcrumbs.length"
          class="flex min-w-0 flex-wrap items-center gap-1 text-body-sm"
          aria-label="Folder path"
        >
          <button
            type="button"
            class="rounded px-1.5 py-0.5 font-medium text-primary-600 hover:bg-primary-50"
            @click="openFolder(null)"
          >
            All folders
          </button>
          <template v-for="crumb in breadcrumbs" :key="crumb.id">
            <span class="text-gray-400" aria-hidden="true">/</span>
            <button
              type="button"
              class="truncate rounded px-1.5 py-0.5 font-medium text-primary-600 hover:bg-primary-50"
              @click="openFolder(crumb.id)"
            >
              {{ crumb.name }}
            </button>
          </template>
        </nav>
        <p v-else class="text-body-sm font-medium text-gray-700">Folders</p>

        <button
          type="button"
          :disabled="busy === 'create-folder'"
          class="rounded-base border border-gray-300 px-3 py-1.5 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50 disabled:opacity-60"
          @click="createPrivateFolder"
        >
          <i class="fas fa-folder-plus mr-1.5" aria-hidden="true"></i>New folder
        </button>
      </div>

      <div v-if="currentFolderId" class="mb-6">
        <UploadZone
          visibility="private"
          :folder-id="currentFolderId"
          @complete="onUploadComplete"
        />
      </div>

      <div v-if="loading" class="space-y-2">
        <div v-for="n in 3" :key="n" class="h-16 animate-pulse rounded-lg bg-gray-100"></div>
      </div>

      <template v-else>
        <section v-if="visibleFolders.length" class="mb-6">
          <ul class="space-y-2">
            <li
              v-for="folder in visibleFolders"
              :key="folder.id"
              class="flex items-center gap-4 rounded-lg border border-gray-200 bg-white p-4"
            >
              <button
                type="button"
                class="flex min-w-0 flex-1 items-center gap-4 text-left"
                @click="openFolder(folder.id)"
              >
                <i class="fas fa-folder text-xl text-warning-500" aria-hidden="true"></i>
                <div class="min-w-0 flex-1">
                  <p class="truncate text-body font-medium text-gray-800">{{ folder.name }}</p>
                  <p class="text-caption text-gray-500">
                    {{ folder.file_count }} {{ folder.file_count === 1 ? "file" : "files" }}
                  </p>
                </div>
              </button>
              <div class="flex shrink-0 items-center gap-1">
                <button
                  type="button"
                  class="rounded-md p-2 text-gray-500 transition hover:bg-gray-100 hover:text-gray-700"
                  :aria-label="`Move ${folder.name}`"
                  title="Move"
                  @click="openMoveFolder(folder)"
                >
                  <i class="fas fa-folder-tree" aria-hidden="true"></i>
                </button>
                <button
                  type="button"
                  class="rounded-md p-2 text-gray-500 transition hover:bg-gray-100 hover:text-gray-700"
                  :aria-label="`Rename ${folder.name}`"
                  title="Rename"
                  @click="renameFolder(folder)"
                >
                  <i class="fas fa-pen" aria-hidden="true"></i>
                </button>
                <button
                  type="button"
                  :disabled="busy === `unlock-${folder.id}`"
                  class="rounded-base border border-gray-300 px-3 py-1.5 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50 disabled:opacity-60"
                  :title="`Move ${folder.name} to My Files`"
                  @click="unlockFolder(folder)"
                >
                  <span v-if="busy === `unlock-${folder.id}`">
                    <i class="fas fa-circle-notch fa-spin" aria-hidden="true"></i>
                  </span>
                  <span v-else>To My Files</span>
                </button>
                <button
                  type="button"
                  :disabled="busy === `trash-folder-${folder.id}`"
                  class="rounded-md p-2 text-gray-500 transition hover:bg-error-50 hover:text-error-600 disabled:opacity-60"
                  :aria-label="`Move ${folder.name} to trash`"
                  @click="trashFolder(folder)"
                >
                  <i
                    :class="['fas', busy === `trash-folder-${folder.id}` ? 'fa-circle-notch fa-spin' : 'fa-trash']"
                    aria-hidden="true"
                  ></i>
                </button>
              </div>
            </li>
          </ul>
        </section>

        <section v-if="allFiles.length" class="mb-6">
          <h2
            v-if="visibleFolders.length || !currentFolderId"
            class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500"
          >
            Files
          </h2>
          <ul class="space-y-2">
            <li
              v-for="file in allFiles"
              :key="file.id"
              class="flex items-center gap-4 rounded-lg border border-gray-200 bg-white p-4"
            >
              <i
                :class="['fas', fileIcon(file).icon, fileIcon(file).className, 'text-xl']"
                aria-hidden="true"
              ></i>
              <div class="min-w-0 flex-1">
                <button
                  type="button"
                  class="block w-full truncate text-left text-body font-medium text-gray-800 hover:text-primary-600"
                  @click="previewFile = file"
                >
                  {{ file.name }}
                </button>
                <p class="text-caption text-gray-500">
                  {{ formatFileSize(file.size) }} · {{ formatRelativeDate(file.created_at) }}
                </p>
              </div>
              <div class="flex shrink-0 items-center gap-1">
                <button
                  type="button"
                  class="rounded-md p-2 text-gray-500 transition hover:bg-gray-100 hover:text-gray-700"
                  :aria-label="`Download ${file.name}`"
                  @click="download(file)"
                >
                  <i class="fas fa-download" aria-hidden="true"></i>
                </button>
                <button
                  type="button"
                  class="rounded-md p-2 text-gray-500 transition hover:bg-gray-100 hover:text-gray-700"
                  :aria-label="`Move ${file.name}`"
                  title="Move to folder"
                  @click="openMoveFile(file)"
                >
                  <i class="fas fa-folder-tree" aria-hidden="true"></i>
                </button>
                <button
                  type="button"
                  :disabled="busy === `out-${file.id}`"
                  class="rounded-md p-2 text-gray-500 transition hover:bg-gray-100 hover:text-gray-700 disabled:opacity-60"
                  :aria-label="`Move ${file.name} to My Files`"
                  title="Move to My Files"
                  @click="takeOut(file)"
                >
                  <i
                    :class="['fas', busy === `out-${file.id}` ? 'fa-circle-notch fa-spin' : 'fa-lock-open']"
                    aria-hidden="true"
                  ></i>
                </button>
                <button
                  type="button"
                  :disabled="busy === `trash-${file.id}`"
                  class="rounded-md p-2 text-gray-500 transition hover:bg-error-50 hover:text-error-600 disabled:opacity-60"
                  :aria-label="`Move ${file.name} to trash`"
                  @click="trashFile(file)"
                >
                  <i
                    :class="['fas', busy === `trash-${file.id}` ? 'fa-circle-notch fa-spin' : 'fa-trash']"
                    aria-hidden="true"
                  ></i>
                </button>
              </div>
            </li>
          </ul>
        </section>

        <p
          v-if="!visibleFolders.length && !allFiles.length"
          class="rounded-base bg-gray-50 px-4 py-6 text-body-sm text-gray-500"
        >
          <template v-if="currentFolderId">
            Empty folder. Upload files above.
          </template>
          <template v-else>
            No folders yet. Create one, or in My Files / Photos right-click an item and choose
            <span class="font-medium text-gray-700">Move to Private</span>.
          </template>
        </p>
      </template>
    </template>

    <div
      v-if="movePicker"
      class="fixed inset-0 z-40 flex items-end justify-center bg-gray-900/40 p-4 sm:items-center"
      role="dialog"
      aria-modal="true"
      aria-labelledby="move-picker-title"
      @click.self="movePicker = null"
    >
      <div class="max-h-[80vh] w-full max-w-md overflow-hidden rounded-lg bg-white shadow-lg">
        <div class="border-b border-gray-200 px-4 py-3">
          <h2 id="move-picker-title" class="text-body font-semibold text-gray-800">
            Move “{{ movePicker.item.name }}”
          </h2>
          <p class="mt-0.5 text-caption text-gray-500">Choose a folder</p>
        </div>
        <ul class="max-h-80 overflow-y-auto p-2">
          <li v-if="movePicker.kind === 'folder'">
            <button
              type="button"
              class="flex w-full items-center gap-3 rounded-base px-3 py-2.5 text-left text-body-sm hover:bg-gray-50"
              @click="confirmMove(null)"
            >
              <i class="fas fa-house text-gray-400" aria-hidden="true"></i>
              <span class="font-medium text-gray-800">Top level</span>
            </button>
          </li>
          <li v-for="dest in moveDestinations" :key="dest.folder.id">
            <button
              type="button"
              :disabled="movePicker.excludeIds.has(dest.folder.id)"
              class="flex w-full items-center gap-3 rounded-base px-3 py-2.5 text-left text-body-sm hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-40"
              @click="confirmMove(dest.folder.id)"
            >
              <i class="fas fa-folder text-warning-500" aria-hidden="true"></i>
              <span class="truncate text-gray-800">{{ dest.path }}</span>
            </button>
          </li>
          <li
            v-if="!moveDestinations.length"
            class="px-3 py-6 text-center text-body-sm text-gray-500"
          >
            Create a folder first.
          </li>
        </ul>
        <div class="border-t border-gray-200 px-4 py-3 text-right">
          <button
            type="button"
            class="rounded-base px-3 py-1.5 text-body-sm font-medium text-gray-600 hover:bg-gray-50"
            @click="movePicker = null"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>

    <FilePreview v-if="previewFile" :file="previewFile" @close="previewFile = null" />
  </section>
</template>
