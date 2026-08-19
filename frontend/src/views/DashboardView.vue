<script setup>
import { computed, onMounted, reactive, ref } from "vue";
import { useAuthStore } from "@/stores/auth";
import { useFilesStore } from "@/stores/files";
import { useLibraryStore } from "@/stores/library";
import UploadZone from "@/components/files/UploadZone.vue";
import ShareModal from "@/components/files/ShareModal.vue";
import LabelPicker from "@/components/files/LabelPicker.vue";
import FilePreview from "@/components/files/FilePreview.vue";
import FileDetails from "@/components/files/FileDetails.vue";
import ScanModal from "@/components/files/ScanModal.vue";
import FolderTree from "@/components/files/FolderTree.vue";
import FolderRow from "@/components/files/FolderRow.vue";
import FilterBar from "@/components/files/FilterBar.vue";
import { useDragAndDrop } from "@/composables/useDragAndDrop";
import { useContextMenu } from "@/composables/useContextMenu";
import { useDialog } from "@/composables/useDialog";
import ContextMenu from "@/components/ui/ContextMenu.vue";
import { formatFileSize, formatRelativeDate, fileIcon } from "@/utils/formatting";

const auth = useAuthStore();
const filesStore = useFilesStore();
const library = useLibraryStore();
const { dragging, dropTargetId, startDrag, endDrag, onDragOver, onDragLeave } = useDragAndDrop();
const contextMenu = useContextMenu();
const dialog = useDialog();

const search = ref("");
const visibility = ref("private");
const sharingFile = ref(null);
const previewFile = ref(null);
const detailsFile = ref(null);
const scanning = ref(false);
// Ids whose thumbnail failed to load (expired URL, or never generated).
const brokenThumbnails = reactive(new Set());
const labellingFile = ref(null);
const showNewFolder = ref(false);
const refreshing = ref(false);

const filters = ref({
  sort: "newest",
  owner_id: "",
  visibility: "",
  date_from: "",
  date_to: "",
  label_ids: [],
});
const newFolderName = ref("");
let searchTimer = null;

// While searching, look across every folder — a search confined to the current
// folder is rarely what anyone means.
const searching = computed(() => search.value.trim().length > 0);

// A label filter is the same kind of cross-cutting view: "show me everything
// tagged Taxes", not "everything tagged Taxes in this one folder".
const filteringByLabel = computed(() => library.selectedLabelIds.length > 0);
const barFiltersActive = computed(() => {
  const f = filters.value;
  return Boolean(f.owner_id || f.visibility || f.date_from || f.date_to || f.label_ids.length);
});

const ignoreFolder = computed(
  () => searching.value || filteringByLabel.value || barFiltersActive.value,
);

// Folders shown inline above the files, like Drive. Hidden while searching or
// filtering, where results deliberately span the whole tree.
const visibleFolders = computed(() =>
  ignoreFolder.value ? [] : library.childFolders(library.currentFolderId ?? null),
);

const isEmptyView = computed(
  () => !filesStore.loading && visibleFolders.value.length === 0 && filesStore.items.length === 0,
);

const heading = computed(() => {
  if (searching.value) return `Results for "${search.value.trim()}"`;
  if (filteringByLabel.value) {
    const names = library.selectedLabelIds
      .map((id) => library.labelsById[id]?.name)
      .filter(Boolean);
    return names.length ? `Labelled ${names.join(" + ")}` : "Filtered";
  }
  return library.currentFolder?.name ?? "My Files";
});

onMounted(async () => {
  await Promise.all([library.fetchFolders(), library.fetchLabels()]);
  load();
});

function load() {
  const { label_ids: barLabels, ...rest } = filters.value;

  filesStore.fetchFiles({
    // Documents only — photos have their own gallery, as the docs specify
    // ("Files Section" and "Images Section"). Searching still spans both.
    fileType: searching.value ? null : "file",
    // undefined = every folder; "" = the root only.
    folderId: ignoreFolder.value ? undefined : (library.currentFolderId ?? ""),
    // Labels can come from the sidebar or the filter bar; either should work.
    labelIds: library.selectedLabelIds.length ? library.selectedLabelIds : barLabels,
    q: search.value.trim(),
    filters: rest,
  });
}

/** Refetches everything on screen — the list, the folder tree and the labels. */
async function refresh() {
  refreshing.value = true;
  try {
    await Promise.all([library.fetchFolders(), library.fetchLabels(), load()]);
  } finally {
    refreshing.value = false;
  }
}

function onSearch() {
  // Debounced so typing doesn't fire a request per keystroke.
  clearTimeout(searchTimer);
  searchTimer = setTimeout(load, 300);
}

async function openFolder(folderId) {
  search.value = "";
  await library.openFolder(folderId);
  load();
}

function toggleLabel(labelId) {
  library.toggleLabelFilter(labelId);
  load();
}

function clearLabels() {
  library.clearLabelFilter();
  load();
}

async function createFolder() {
  const name = newFolderName.value.trim();
  if (!name) return;

  try {
    await library.createFolder({
      name,
      parentId: library.currentFolderId ?? null,
      // A folder made inside the family tree stays shared; at the root the
      // upload-visibility choice decides.
      shared: visibility.value === "family",
    });
    newFolderName.value = "";
    showNewFolder.value = false;
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

/* ------------------------------------------------------------------ menus */

async function promptRenameFile(file) {
  const name = await dialog.prompt({
    title: "Rename file",
    label: "File name",
    value: file.name,
    confirmLabel: "Rename",
  });
  if (!name || name === file.name) return;

  try {
    await filesStore.rename(file, name);
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

async function promptRenameFolder(folder) {
  const name = await dialog.prompt({
    title: "Rename folder",
    label: "Folder name",
    value: folder.name,
    confirmLabel: "Rename",
  });
  if (!name || name === folder.name) return;

  await renameFolder({ folder, name });
}

async function promptNewSubfolder(folder) {
  const name = await dialog.prompt({
    title: `New folder inside "${folder.name}"`,
    label: "Folder name",
    placeholder: "e.g. Receipts",
    confirmLabel: "Create",
  });
  if (!name) return;

  try {
    await library.createFolder({ name, parentId: folder.id, shared: folder.shared });
    load();
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

async function moveToRoot(payload) {
  await handleDrop({ payload, targetFolderId: null });
}

function fileMenu(event, file) {
  contextMenu.open(event, {
    title: file.name,
    items: [
      { label: "Preview", icon: "fa-eye", action: () => (previewFile.value = file) },
      { label: "Download", icon: "fa-download", action: () => onDownload(file) },
      { label: "Details", icon: "fa-circle-info", action: () => (detailsFile.value = file) },
      file.permissions.can_share && {
        label: "Share…", icon: "fa-share-nodes", action: () => (sharingFile.value = file),
      },
      file.permissions.can_edit && {
        label: "Labels…", icon: "fa-tag", action: () => (labellingFile.value = file),
      },
      { divider: true },
      file.permissions.can_edit && {
        label: "Rename…", icon: "fa-pen", action: () => promptRenameFile(file),
      },
      file.permissions.can_edit && file.folder && {
        label: "Move to top level", icon: "fa-arrow-turn-up",
        action: () => moveToRoot({ type: "file", id: file.id, name: file.name }),
      },
      file.permissions.can_delete && { divider: true },
      file.permissions.can_delete && {
        label: "Move to trash", icon: "fa-trash", danger: true, action: () => onTrash(file),
      },
    ],
  });
}

async function downloadFolder(folder) {
  try {
    await library.downloadFolder(folder);
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

function folderMenu(event, folder) {
  contextMenu.open(event, {
    title: folder.name,
    items: [
      { label: "Open", icon: "fa-folder-open", action: () => openFolder(folder.id) },
      {
        label: "Download as ZIP",
        icon: "fa-file-zipper",
        // Includes everything nested inside, not just the top level.
        action: () => downloadFolder(folder),
      },
      { label: "New folder inside", icon: "fa-folder-plus", action: () => promptNewSubfolder(folder) },
      { divider: true },
      { label: "Rename…", icon: "fa-pen", action: () => promptRenameFolder(folder) },
      folder.parent_id && {
        label: "Move to top level", icon: "fa-arrow-turn-up",
        action: () => moveToRoot({ type: "folder", id: folder.id, name: folder.name }),
      },
      { divider: true },
      {
        label: "Move to trash", icon: "fa-trash", danger: true,
        action: () => deleteFolder(folder),
      },
    ],
  });
}

function labelMenu(event, label) {
  const active = library.selectedLabelIds.includes(label.id);

  contextMenu.open(event, {
    title: label.name,
    items: [
      {
        label: active ? "Remove filter" : "Filter by this label",
        icon: active ? "fa-filter-circle-xmark" : "fa-filter",
        action: () => toggleLabel(label.id),
      },
      { divider: true },
      {
        label: "Rename…",
        icon: "fa-pen",
        action: async () => {
          const name = await dialog.prompt({
            title: "Rename label",
            label: "Label name",
            value: label.name,
            confirmLabel: "Rename",
          });
          if (!name || name === label.name) return;
          try {
            await library.renameLabel(label, name);
            load();
          } catch (e) {
            filesStore.error = e.userMessage;
          }
        },
      },
      {
        label: "Delete label", icon: "fa-trash", danger: true,
        action: async () => {
          const ok = await dialog.confirm({
            title: `Delete "${label.name}"?`,
            message: "The label is removed from every file. The files themselves are untouched.",
            confirmLabel: "Delete label",
            danger: true,
          });
          if (!ok) return;

          await library.deleteLabel(label);
          load();
        },
      },
    ],
  });
}

// Right-clicking empty space in the listing acts on the current folder.
function backgroundMenu(event) {
  contextMenu.open(event, {
    title: library.currentFolder?.name ?? "All files",
    items: [
      { label: "New folder", icon: "fa-folder-plus", action: () => (showNewFolder.value = true) },
      { label: "Upload files", icon: "fa-cloud-arrow-up", action: () => document.querySelector('input[type="file"]')?.click() },
    ],
  });
}

/**
 * Handles every drop: a file or folder onto a folder row, a tree node, a
 * breadcrumb, or the "All files" root.
 */
async function handleDrop({ payload, targetFolderId }) {
  try {
    if (payload.type === "file") {
      const file = filesStore.items.find((f) => f.id === payload.id);
      if (file) await filesStore.move(file, targetFolderId);
    } else {
      // Moving into a descendant is blocked before the drop, and the API
      // rejects it too.
      const folder = library.folders.find((f) => f.id === payload.id);
      if (folder) await library.moveFolder(folder, targetFolderId);
    }

    await library.fetchFolders();
    load();
  } catch (e) {
    filesStore.error = e.userMessage ?? "That move isn't allowed.";
  }
}

function onRootDrop(event) {
  event.preventDefault();
  const payload = dragging.value;
  endDrag();
  // null moves the item back to the top level.
  if (payload) handleDrop({ payload, targetFolderId: null });
}

async function renameFolder({ folder, name }) {
  try {
    await library.renameFolder(folder, name);
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

async function deleteFolder(folder) {
  const ok = await dialog.confirm({
    title: `Move "${folder.name}" to trash?`,
    message: folder.file_count
      ? `Everything inside goes with it — ${folder.file_count} ${folder.file_count === 1 ? "file" : "files"} and any subfolders.`
      : "Any subfolders go with it.",
    detail: "You can restore the whole folder from Trash for 30 days.",
    confirmLabel: "Move to trash",
    danger: true,
  });
  if (!ok) return;

  await library.deleteFolder(folder);
  load();
}

async function onTrash(file) {
  const ok = await dialog.confirm({
    title: `Move "${file.name}" to trash?`,
    message: "You can restore it from Trash for 30 days.",
    confirmLabel: "Move to trash",
    danger: true,
  });
  if (!ok) return;

  await filesStore.trash(file);
  library.fetchFolders();
}

async function onDownload(file) {
  try {
    await filesStore.download(file);
  } catch (error) {
    filesStore.error = error.userMessage;
  }
}

// Offer sharing immediately after an upload — that is usually why the file was
// uploaded in the first place.
function onUploaded(file) {
  library.fetchFolders();
  if (file.permissions.can_share) sharingFile.value = file;
}
</script>

<template>
  <div class="flex gap-6">
    <!-- Folder tree. Hidden on small screens, where breadcrumbs are enough. -->
    <aside class="hidden w-56 shrink-0 lg:block">
      <div class="mb-2 flex items-center justify-between">
        <h2 class="text-label font-medium uppercase tracking-wide text-gray-500">Folders</h2>
        <button
          type="button"
          class="rounded p-1 text-gray-400 transition hover:bg-gray-100 hover:text-primary-600"
          aria-label="New folder"
          @click="showNewFolder = !showNewFolder"
        >
          <i class="fas fa-folder-plus" aria-hidden="true"></i>
        </button>
      </div>

      <form v-if="showNewFolder" class="mb-2 flex gap-1" @submit.prevent="createFolder">
        <label for="new-folder" class="sr-only">Folder name</label>
        <input
          id="new-folder"
          v-model="newFolderName"
          type="text"
          placeholder="Folder name"
          class="w-full rounded-base border border-gray-300 px-2 py-1 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
        />
        <button
          type="submit"
          class="shrink-0 rounded-base bg-primary-600 px-2 text-body-sm font-medium text-white"
        >
          Add
        </button>
      </form>

      <button
        type="button"
        :class="[
          'mb-1 flex w-full items-center gap-2 rounded-base px-2 py-1.5 text-body-sm transition',
          dropTargetId === 'root'
            ? 'bg-primary-100 ring-2 ring-primary-400'
            : library.currentFolderId === null
              ? 'bg-primary-50 text-primary-700'
              : 'text-gray-600 hover:bg-gray-100',
        ]"
        @click="openFolder(null)"
        @dragover="onDragOver($event, 'root')"
        @dragleave="onDragLeave('root')"
        @drop="onRootDrop"
      >
        <i class="fas fa-house w-4 text-caption" aria-hidden="true"></i>
        All files
      </button>

      <FolderTree :nodes="library.tree" @open="openFolder" @drop="handleDrop" @menu="folderMenu" />

      <p v-if="!library.tree.length" class="px-2 py-2 text-caption text-gray-400">
        No folders yet.
      </p>

      <!-- Label filter -->
      <div v-if="library.labels.length" class="mt-6">
        <div class="mb-2 flex items-center justify-between">
          <h2 class="text-label font-medium uppercase tracking-wide text-gray-500">Labels</h2>
          <button
            v-if="library.selectedLabelIds.length"
            type="button"
            class="text-caption text-primary-600 hover:underline"
            @click="clearLabels"
          >
            Clear
          </button>
        </div>

        <ul class="space-y-0.5">
          <li v-for="label in library.labels" :key="label.id">
            <button
              type="button"
              :aria-pressed="library.selectedLabelIds.includes(label.id)"
              :class="[
                'flex w-full items-center gap-2 rounded-base px-2 py-1.5 text-body-sm transition',
                library.selectedLabelIds.includes(label.id)
                  ? 'bg-primary-50 text-primary-700'
                  : 'text-gray-600 hover:bg-gray-100',
              ]"
              @click="toggleLabel(label.id)"
              @contextmenu="labelMenu($event, label)"
            >
              <span
                class="h-2.5 w-2.5 shrink-0 rounded-full"
                :style="{ backgroundColor: label.color }"
                aria-hidden="true"
              ></span>
              <span class="flex-1 truncate text-left">{{ label.name }}</span>
              <span class="text-caption text-gray-400">{{ label.files_count }}</span>
            </button>
          </li>
        </ul>
      </div>
    </aside>

    <section class="flex min-h-[70vh] min-w-0 flex-1 flex-col">
      <!-- Breadcrumbs -->
      <nav v-if="library.breadcrumbs.length && !searching" class="mb-2" aria-label="Breadcrumb">
        <ol class="flex flex-wrap items-center gap-1 text-body-sm text-gray-500">
          <li>
            <button
              type="button"
              :class="['rounded px-1 hover:text-primary-600', dropTargetId === 'root' ? 'bg-primary-100' : '']"
              @click="openFolder(null)"
              @dragover="onDragOver($event, 'root')"
              @dragleave="onDragLeave('root')"
              @drop="onRootDrop"
            >
              All files
            </button>
          </li>
          <li v-for="crumb in library.breadcrumbs" :key="crumb.id" class="flex items-center gap-1">
            <i class="fas fa-chevron-right text-caption text-gray-300" aria-hidden="true"></i>
            <button
              type="button"
              :class="[
                'rounded px-1 hover:text-primary-600',
                dropTargetId === crumb.id ? 'bg-primary-100 ring-1 ring-primary-400' : '',
              ]"
              :aria-current="crumb.id === library.currentFolderId ? 'page' : undefined"
              @click="openFolder(crumb.id)"
              @dragover="onDragOver($event, crumb.id, { descendantIds: library.descendantIds(crumb.id) })"
              @dragleave="onDragLeave(crumb.id)"
              @drop="(e) => { e.preventDefault(); const p = dragging; endDrag(); if (p) handleDrop({ payload: p, targetFolderId: crumb.id }); }"
            >
              {{ crumb.name }}
            </button>
          </li>
        </ol>
      </nav>

      <header class="mb-6 flex flex-wrap items-center justify-between gap-4">
        <div class="min-w-0">
          <h1 class="truncate text-h2 font-bold text-gray-800">{{ heading }}</h1>
          <p class="mt-1 text-body-sm text-gray-500">
            {{ filesStore.totalCount }} {{ filesStore.totalCount === 1 ? "file" : "files" }}
            <template v-if="auth.user">
              · {{ formatFileSize(auth.user.storage_used) }} of
              {{ formatFileSize(auth.user.storage_quota) }} used
            </template>
          </p>
        </div>

        <div class="flex items-center gap-3">
          <label for="file-search" class="sr-only">Search files</label>
          <div class="relative">
            <i
              class="fas fa-magnifying-glass pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-gray-400"
              aria-hidden="true"
            ></i>
            <input
              id="file-search"
              v-model="search"
              type="search"
              placeholder="Search name or label"
              class="w-56 rounded-base border border-gray-300 py-2 pl-9 pr-3 text-body outline-none focus:border-transparent focus:ring-2 focus:ring-primary-500"
              @input="onSearch"
            />
          </div>

          <button
            type="button"
            :disabled="refreshing"
            class="rounded-base border border-gray-300 px-3 py-2 text-body font-medium text-gray-700 transition hover:bg-gray-50 disabled:opacity-60"
            aria-label="Refresh"
            @click="refresh"
          >
            <i :class="['fas fa-rotate-right', refreshing ? 'fa-spin' : '']" aria-hidden="true"></i>
          </button>

          <button
            type="button"
            class="rounded-base border border-gray-300 px-3 py-2 text-body font-medium text-gray-700 transition hover:bg-gray-50"
            @click="scanning = true"
          >
            <i class="fas fa-qrcode mr-2" aria-hidden="true"></i>Scan
          </button>

          <label for="visibility" class="sr-only">Upload visibility</label>
          <select
            id="visibility"
            v-model="visibility"
            class="rounded-base border border-gray-300 px-3 py-2 text-body outline-none focus:ring-2 focus:ring-primary-500"
          >
            <option value="private">Only me</option>
            <option value="family" :disabled="!auth.canEdit">Share with family</option>
          </select>
        </div>
      </header>

      <FilterBar v-model="filters" class="mb-4" @change="load" />

      <UploadZone
        :visibility="visibility"
        :folder-id="library.currentFolderId"
        class="mb-6"
        @uploaded="onUploaded"
      />

      <p
        v-if="filesStore.error"
        role="alert"
        class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
      >
        {{ filesStore.error }}
      </p>

      <!-- flex-1 so blank space under the list belongs here; .self then makes
           the background right-click reachable. -->
      <div class="flex-1" @contextmenu.self="backgroundMenu">
      <!-- Loading skeleton keeps the layout from jumping when results land. -->
      <div v-if="filesStore.loading" class="space-y-2">
        <div v-for="n in 4" :key="n" class="h-16 animate-pulse rounded-lg bg-gray-100"></div>
      </div>

      <div
        v-else-if="isEmptyView"
        class="rounded-lg border border-gray-200 bg-white p-12 text-center"
      >
        <i class="fas fa-folder-open text-4xl text-gray-300" aria-hidden="true"></i>
        <h2 class="mt-4 text-h3 font-semibold text-gray-800">
          {{ searching ? "No files match that search" : filteringByLabel ? "No files carry that label" : "Nothing here yet" }}
        </h2>
        <p class="mt-2 text-body text-gray-500">
          {{
            searching
              ? "Try a different term, or search by label name."
              : filteringByLabel
                ? "Add the label to a file from its label button."
                : "Upload a file above."
          }}
        </p>
      </div>

      <ul v-else class="space-y-2">
        <!-- Folders sit above files, like Drive; drag a row onto one to move it. -->
        <FolderRow
          v-for="folder in visibleFolders"
          :key="`folder-${folder.id}`"
          :folder="folder"
          @contextmenu="folderMenu($event, folder)"
          @open="openFolder"
          @drop="handleDrop"
          @rename="renameFolder"
          @delete="deleteFolder"
          @download="downloadFolder"
        />

        <li
          v-for="file in filesStore.items"
          :key="file.id"
          draggable="true"
          :class="[
            'flex items-center gap-4 rounded-lg border border-gray-200 bg-white p-4 transition',
            dragging?.type === 'file' && dragging.id === file.id ? 'opacity-40' : 'hover:shadow-md',
          ]"
          @dragstart="startDrag($event, 'file', file)"
          @dragend="endDrag"
          @contextmenu="fileMenu($event, file)"
        >
          <!-- Presigned thumbnail URLs expire; if one has, fall back to the
               icon rather than leaving a broken image in the row. -->
          <img
            v-if="file.image?.thumbnail_url && !brokenThumbnails.has(file.id)"
            :src="file.image.thumbnail_url"
            :alt="file.name"
            class="h-10 w-10 shrink-0 rounded object-cover"
            loading="lazy"
            @error="brokenThumbnails.add(file.id)"
          />
          <i
            v-else
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
              <span v-if="file.version_number > 1"> · v{{ file.version_number }}</span>
              <!-- Where a file lives matters most when results span folders -->
              <span v-if="file.folder"> · {{ file.folder.name }}</span>
              · {{ file.owner.name }}
            </p>

            <ul v-if="file.labels?.length" class="mt-1 flex flex-wrap gap-1">
              <li
                v-for="label in file.labels"
                :key="label.id"
                class="rounded-full px-2 py-0.5 text-caption"
                :style="{ backgroundColor: `${label.color}1A`, color: label.color }"
              >
                {{ label.name }}
              </li>
            </ul>
          </div>

          <span
            v-if="file.visibility === 'family'"
            class="rounded-full bg-primary-50 px-2 py-1 text-label font-medium text-primary-700"
          >
            <i class="fas fa-users mr-1" aria-hidden="true"></i>Family
          </span>

          <div class="flex items-center gap-1">
            <button
              type="button"
              class="rounded-md p-2 text-gray-500 transition hover:bg-gray-100 hover:text-gray-700"
              :aria-label="`Preview ${file.name}`"
              @click="previewFile = file"
            >
              <i class="fas fa-eye" aria-hidden="true"></i>
            </button>
            <button
              v-if="file.permissions.can_edit"
              type="button"
              class="rounded-md p-2 text-gray-500 transition hover:bg-gray-100 hover:text-gray-700"
              :aria-label="`Edit labels for ${file.name}`"
              @click="labellingFile = file"
            >
              <i class="fas fa-tag" aria-hidden="true"></i>
            </button>
            <button
              v-if="file.permissions.can_share"
              type="button"
              class="rounded-md p-2 text-gray-500 transition hover:bg-primary-50 hover:text-primary-600"
              :aria-label="`Share ${file.name}`"
              @click="sharingFile = file"
            >
              <i class="fas fa-share-nodes" aria-hidden="true"></i>
            </button>
            <button
              type="button"
              class="rounded-md p-2 text-gray-500 transition hover:bg-gray-100 hover:text-gray-700"
              :aria-label="`Download ${file.name}`"
              @click="onDownload(file)"
            >
              <i class="fas fa-download" aria-hidden="true"></i>
            </button>
            <button
              v-if="file.permissions.can_delete"
              type="button"
              class="rounded-md p-2 text-gray-500 transition hover:bg-error-50 hover:text-error-600"
              :aria-label="`Move ${file.name} to trash`"
              @click="onTrash(file)"
            >
              <i class="fas fa-trash" aria-hidden="true"></i>
            </button>
          </div>
        </li>
      </ul>
      </div>

      <ContextMenu />

      <FilePreview
        v-if="previewFile"
        :file="previewFile"
        :files="filesStore.items"
        @navigate="previewFile = $event"
        @close="previewFile = null"
      />

      <ShareModal v-if="sharingFile" :file="sharingFile" @close="sharingFile = null" />

      <FileDetails v-if="detailsFile" :file="detailsFile" @close="detailsFile = null" />

      <ScanModal
        v-if="scanning"
        :folder-id="library.currentFolderId"
        :visibility="visibility"
        @uploaded="load(); library.fetchFolders()"
        @close="scanning = false"
      />
      <LabelPicker v-if="labellingFile" :file="labellingFile" @close="labellingFile = null" />
    </section>
  </div>
</template>
