<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import { useFilesStore } from "@/stores/files";
import { useLibraryStore } from "@/stores/library";
import InvitationBanner from "@/components/family/InvitationBanner.vue";
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
import { useToast } from "@/composables/useToast";
import { useVaultGate } from "@/composables/useVaultGate";
import { usePrivateDestination } from "@/composables/usePrivateDestination";
import { useSelection } from "@/composables/useSelection";
import ContextMenu from "@/components/ui/ContextMenu.vue";
import BulkActionBar from "@/components/ui/BulkActionBar.vue";
import InlineName from "@/components/ui/InlineName.vue";
import { formatFileSize, formatRelativeDate, fileIcon } from "@/utils/formatting";
import { useVaultStore } from "@/stores/vault";
import api from "@/api/client";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const filesStore = useFilesStore();
const library = useLibraryStore();
const vault = useVaultStore();
const vaultGate = useVaultGate();
const privateDest = usePrivateDestination();
const {
  count: selectedCount,
  hasSelection,
  isSelected,
  clear: clearSelection,
  onSelect,
  selectedOf,
} = useSelection();
const { dragging, dropTargetId, startDrag, endDrag, onDragOver, onDragLeave } = useDragAndDrop();
const contextMenu = useContextMenu();
const dialog = useDialog();
const toast = useToast();
const bulkBusy = ref(false);

const search = ref("");
const visibility = ref("private");
const sharingFile = ref(null);
const previewFile = ref(null);
const detailsFile = ref(null);
const scanning = ref(false);
// Ids whose thumbnail failed to load (expired URL, or never generated).
const brokenThumbnails = reactive(new Set());
// Rows to flash briefly, so a file that just arrived can be spotted.
const highlighted = reactive(new Set());

function flash(fileId) {
  highlighted.add(fileId);
  setTimeout(() => highlighted.delete(fileId), 4000);

  nextTick(() => {
    document
      .querySelector(`[data-file-id="${fileId}"]`)
      ?.scrollIntoView({ behavior: "smooth", block: "center" });
  });
}
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

function onEscape(event) {
  if (event.key === "Escape" && hasSelection.value) clearSelection();
}

onMounted(async () => {
  window.addEventListener("keydown", onEscape);
  await Promise.all([library.fetchFolders(), library.fetchLabels()]);
  await load();

  // Arriving from "Show me" elsewhere in the app. The folder comes with it:
  // flashing a row is no use if the view is showing a different folder.
  if (route.query.folder !== undefined) {
    await openFolder(route.query.folder === "" ? null : Number(route.query.folder));
  }

  const target = Number(route.query.show);
  if (target) flash(target);
});

onBeforeUnmount(() => window.removeEventListener("keydown", onEscape));

/** Visible rows in order — folders first, then files — for shift-click ranges. */
const selectableItems = computed(() => [
  ...visibleFolders.value.map((folder) => ({ type: "folder", id: folder.id })),
  ...filesStore.items.map((file) => ({ type: "file", id: file.id })),
]);

const bulkActions = computed(() => [
  {
    id: "download",
    label: selectedCount.value > 1 ? "Download ZIP" : "Download",
    icon: selectedCount.value > 1 ? "fa-file-zipper" : "fa-download",
  },
  vault.exists && { id: "private", label: "Move to Private", icon: "fa-lock" },
  { id: "trash", label: "Move to trash", icon: "fa-trash", danger: true },
].filter(Boolean));

const bulkNoun = computed(() => {
  const files = selectedOf("file").length;
  const folders = selectedOf("folder").length;
  if (files && folders) return "item";
  if (folders) return "folder";
  return "file";
});

function load() {
  const { label_ids: barLabels, ...rest } = filters.value;

  // At the My Files root, documents only — photos live in the gallery.
  // Inside a folder, show everything that folder actually holds; otherwise a
  // folder full of photos looks empty while the sidebar still says "64".
  const insideFolder = library.currentFolderId != null && !ignoreFolder.value;

  return filesStore.fetchFiles({
    fileType: searching.value || insideFolder ? null : "file",
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
  clearSelection();
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

/* ---------------------------------------------------------------- naming */

// The row being renamed, if any. One at a time: two open fields would leave the
// user unsure which one Enter was about to commit.
const renamingFileId = ref(null);
const renamingFolderId = ref(null);

function beginRenameFile(file) {
  renamingFolderId.value = null;
  renamingFileId.value = file.id;
}

function beginRenameFolder(folder) {
  renamingFileId.value = null;
  renamingFolderId.value = folder.id;
}

/** Sends a picture back to the gallery, undoing "this is a document". */
async function fileAsPhoto(file) {
  try {
    await filesStore.setFileType(file, "image");

    toast.show({
      message: "Moved to Photos",
      detail: file.name,
      actionLabel: "Undo",
      action: async () => {
        await filesStore.setFileType(file, "file");
        load();
      },
    });
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

async function renameFile(file, name) {
  try {
    await filesStore.rename(file, name);
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

/* ------------------------------------------------------------------ menus */

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

async function moveFileToPrivate(file) {
  if (!(await vaultGate.ensureUnlocked())) return;

  const folderId = await privateDest.pick({ title: `Move "${file.name}" to Private` });
  if (folderId === undefined) return;

  try {
    await filesStore.moveToPrivate(file, folderId);
    toast.show({ message: "Moved to Private", detail: file.name });
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

async function moveFolderToPrivate(folder) {
  if (!(await vaultGate.ensureUnlocked())) return;

  const folderId = await privateDest.pick({
    title: `Move "${folder.name}" to Private`,
    allowRoot: true,
  });
  if (folderId === undefined) return;

  try {
    const body = { folder_id: folderId ?? "" };
    const { data } = await api.post(`/folders/${folder.id}/lock`, body);
    toast.show({
      message: `${folder.name} is private now`,
      detail: `${data.files} file${data.files === 1 ? "" : "s"} encrypted`,
    });
    await Promise.all([library.fetchFolders(), load()]);
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

function fileMenu(event, file) {
  // Right-clicking inside a multi-selection acts on everything selected.
  if (
    selectedCount.value > 1 &&
    isSelected("file", file.id)
  ) {
    contextMenu.open(event, {
      title: `${selectedCount.value} selected`,
      items: [
        { label: "Download as ZIP", icon: "fa-file-zipper", action: () => runBulk("download") },
        vault.exists && {
          label: "Move to Private", icon: "fa-lock", action: () => runBulk("private"),
        },
        { divider: true },
        {
          label: "Move to trash", icon: "fa-trash", danger: true, action: () => runBulk("trash"),
        },
      ],
    });
    return;
  }

  contextMenu.open(event, {
    title: file.name,
    items: [
      { label: "Preview", icon: "fa-eye", action: () => (previewFile.value = file) },
      { label: "Download", icon: "fa-download", action: () => onDownload(file) },
      { label: "Details", icon: "fa-circle-info", action: () => (detailsFile.value = file) },
      file.mime_type === "application/pdf" && file.permissions.can_edit && {
        label: "Sign & fill…",
        icon: "fa-signature",
        action: () => router.push({ name: "sign-editor", params: { id: file.id } }),
      },
      file.permissions.can_share && {
        label: "Share…", icon: "fa-share-nodes", action: () => (sharingFile.value = file),
      },
      file.permissions.can_edit && {
        label: "Labels…", icon: "fa-tag", action: () => (labellingFile.value = file),
      },
      { divider: true },
      file.permissions.can_edit && {
        label: "Rename", icon: "fa-pen", action: () => beginRenameFile(file),
      },
      file.permissions.can_edit && file.folder && {
        label: "Move to top level", icon: "fa-arrow-turn-up",
        action: () => moveToRoot({ type: "file", id: file.id, name: file.name }),
      },
      // Only for a file that is a picture in the first place — the rest have
      // nowhere to go.
      file.permissions.can_edit && file.filed_as_document && {
        label: "Move to Photos", icon: "fa-image", action: () => fileAsPhoto(file),
      },
      file.permissions.can_edit && vault.exists && {
        label: "Move to Private", icon: "fa-lock", action: () => moveFileToPrivate(file),
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
  if (
    selectedCount.value > 1 &&
    isSelected("folder", folder.id)
  ) {
    contextMenu.open(event, {
      title: `${selectedCount.value} selected`,
      items: [
        { label: "Download as ZIP", icon: "fa-file-zipper", action: () => runBulk("download") },
        vault.exists && {
          label: "Move to Private", icon: "fa-lock", action: () => runBulk("private"),
        },
        { divider: true },
        {
          label: "Move to trash", icon: "fa-trash", danger: true, action: () => runBulk("trash"),
        },
      ],
    });
    return;
  }

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
      { label: "Rename", icon: "fa-pen", action: () => beginRenameFolder(folder) },
      folder.parent_id && {
        label: "Move to top level", icon: "fa-arrow-turn-up",
        action: () => moveToRoot({ type: "folder", id: folder.id, name: folder.name }),
      },
      vault.exists && {
        label: "Move to Private", icon: "fa-lock", action: () => moveFolderToPrivate(folder),
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

function onUploaded(file) {
  library.fetchFolders();
  flash(file.id);
}

// One toast for the whole batch — uploading ten photos used to stack ten.
function onUploadComplete({ uploaded, failed }) {
  if (!uploaded.length) {
    if (failed) toast.show({ message: "Upload failed", tone: "error" });
    return;
  }

  if (uploaded.length === 1) {
    const file = uploaded[0];
    const where = file.folder?.name ?? "Top level";
    toast.show({
      message: `Uploaded to ${where}`,
      detail: file.name,
      actionLabel: "Show me",
      action: () => {
        openFolder(file.folder?.id ?? null).then(() => flash(file.id));
      },
    });
    return;
  }

  toast.show({
    message: `Uploaded ${uploaded.length} files`,
    detail: failed ? `${failed} failed` : (uploaded[0].folder?.name ?? "Top level"),
  });
}

function selectFile(event, file) {
  onSelect("file", file.id, event, selectableItems.value);
}

function selectFolder(event, folder) {
  onSelect("folder", folder.id, event, selectableItems.value);
}

async function runBulk(actionId) {
  if (bulkBusy.value) return;

  const fileIds = selectedOf("file");
  const folderIds = selectedOf("folder");
  const files = fileIds
    .map((id) => filesStore.items.find((f) => String(f.id) === String(id)))
    .filter(Boolean);
  const folders = folderIds
    .map((id) => visibleFolders.value.find((f) => String(f.id) === String(id)))
    .filter(Boolean);

  if (!files.length && !folders.length) return;

  bulkBusy.value = true;
  try {
    if (actionId === "download") await bulkDownload(files, folders);
    else if (actionId === "private") await bulkMoveToPrivate(files, folders);
    else if (actionId === "trash") await bulkTrash(files, folders);
  } finally {
    bulkBusy.value = false;
  }
}

async function bulkDownload(files, folders) {
  // Several loose files → one ZIP. Folders already have their own ZIP endpoint.
  if (files.length > 1 && folders.length === 0) {
    try {
      await filesStore.downloadZip(files.map((f) => f.id));
      toast.show({ message: `Downloading ${files.length} files as ZIP` });
    } catch (e) {
      filesStore.error = e.userMessage;
    }
    return;
  }

  if (files.length === 1 && folders.length === 0) {
    try {
      await filesStore.download(files[0]);
    } catch (e) {
      filesStore.error = e.userMessage;
    }
    return;
  }

  for (const folder of folders) {
    try {
      await library.downloadFolder(folder);
    } catch (e) {
      filesStore.error = e.userMessage;
    }
  }
  if (files.length === 1) {
    try {
      await filesStore.download(files[0]);
    } catch (e) {
      filesStore.error = e.userMessage;
    }
  } else if (files.length > 1) {
    try {
      await filesStore.downloadZip(files.map((f) => f.id));
    } catch (e) {
      filesStore.error = e.userMessage;
    }
  }
}

async function bulkMoveToPrivate(files, folders) {
  if (!(await vaultGate.ensureUnlocked())) return;

  const folderId = await privateDest.pick({
    title: `Move ${files.length + folders.length} items to Private`,
    allowRoot: folders.length > 0 && files.length === 0,
  });
  if (folderId === undefined) return;

  // Files need a real folder; if only folders were selected, root (null) is fine.
  if (files.length && folderId == null) {
    filesStore.error = "Pick a private folder for the files.";
    return;
  }

  let moved = 0;
  try {
    for (const folder of folders) {
      await api.post(`/folders/${folder.id}/lock`, { folder_id: folderId ?? "" });
      moved += 1;
    }
    for (const file of files) {
      await filesStore.moveToPrivate(file, folderId);
      moved += 1;
    }
    toast.show({
      message: `Moved ${moved} ${moved === 1 ? "item" : "items"} to Private`,
    });
    clearSelection();
    await Promise.all([library.fetchFolders(), load()]);
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

async function bulkTrash(files, folders) {
  const n = files.length + folders.length;
  const ok = await dialog.confirm({
    title: `Move ${n} ${n === 1 ? "item" : "items"} to trash?`,
    message: "You can restore them from Trash for 30 days.",
    confirmLabel: "Move to trash",
    danger: true,
  });
  if (!ok) return;

  try {
    for (const folder of folders) {
      await library.deleteFolder(folder);
    }
    for (const file of files) {
      await filesStore.trash(file);
    }
    toast.show({
      message: `Moved ${n} ${n === 1 ? "item" : "items"} to trash`,
    });
    clearSelection();
    await Promise.all([library.fetchFolders(), load()]);
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}
</script>

<template>
  <!-- Being asked to join a family is the first thing you should see, and the
       one thing that used to live only in an email. -->
  <InvitationBanner />

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
        @complete="onUploadComplete"
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
          :editing="renamingFolderId === folder.id"
          :selected="isSelected('folder', folder.id)"
          :selecting="hasSelection"
          @contextmenu="folderMenu($event, folder)"
          @update:editing="renamingFolderId = $event ? folder.id : null"
          @open="openFolder"
          @drop="handleDrop"
          @rename="renameFolder"
          @delete="deleteFolder"
          @download="downloadFolder"
          @select="selectFolder($event, folder)"
        />

        <li
          v-for="file in filesStore.items"
          :key="file.id"
          :data-file-id="file.id"
          :draggable="renamingFileId !== file.id"
          :class="[
            'group flex items-center gap-3 rounded-lg border bg-white p-4 transition',
            isSelected('file', file.id)
              ? 'border-primary-500 bg-primary-50/40 ring-2 ring-primary-200'
              : highlighted.has(file.id)
                ? 'border-primary-500 ring-2 ring-primary-200'
                : 'border-gray-200',
            dragging?.type === 'file' && dragging.id === file.id ? 'opacity-40' : 'hover:shadow-md',
          ]"
          @dragstart="startDrag($event, 'file', file)"
          @dragend="endDrag"
          @contextmenu="fileMenu($event, file)"
        >
          <button
            type="button"
            data-select-toggle
            :class="[
              'flex h-5 w-5 shrink-0 items-center justify-center rounded border transition',
              isSelected('file', file.id)
                ? 'border-primary-600 bg-primary-600 text-white'
                : 'border-gray-300 text-transparent hover:border-primary-400',
              hasSelection || isSelected('file', file.id)
                ? 'opacity-100'
                : 'opacity-0 group-hover:opacity-100 focus-visible:opacity-100',
            ]"
            :aria-label="isSelected('file', file.id) ? `Deselect ${file.name}` : `Select ${file.name}`"
            :aria-pressed="isSelected('file', file.id)"
            @click="selectFile($event, file)"
          >
            <i class="fas fa-check text-[10px]" aria-hidden="true"></i>
          </button>

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
            <InlineName
              :name="file.name"
              :editing="renamingFileId === file.id"
              :input-id="`rename-file-${file.id}`"
              label="File name"
              keep-extension
              @update:editing="renamingFileId = $event ? file.id : null"
              @rename="renameFile(file, $event)"
              @open="previewFile = file"
            />
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
              :aria-label="`Rename ${file.name}`"
              @click="beginRenameFile(file)"
            >
              <i class="fas fa-pen" aria-hidden="true"></i>
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

      <BulkActionBar
        v-if="hasSelection"
        :count="selectedCount"
        :noun="bulkNoun"
        :actions="bulkActions"
        :busy="bulkBusy"
        @action="runBulk"
        @clear="clearSelection"
      />

      <ContextMenu />

      <FilePreview
        v-if="previewFile"
        :file="previewFile"
        :files="filesStore.items"
        @navigate="previewFile = $event"
        @close="previewFile = null"
      />

      <ShareModal v-if="sharingFile" kind="file" :subject="sharingFile" @close="sharingFile = null" />

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
