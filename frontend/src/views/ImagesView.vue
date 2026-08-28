<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { useAuthStore } from "@/stores/auth";
import { useFilesStore } from "@/stores/files";
import { useVaultStore } from "@/stores/vault";
import { useContextMenu } from "@/composables/useContextMenu";
import { useDialog } from "@/composables/useDialog";
import { useToast } from "@/composables/useToast";
import { useVaultGate } from "@/composables/useVaultGate";
import { usePrivateDestination } from "@/composables/usePrivateDestination";
import { useSelection } from "@/composables/useSelection";
import { useMarqueeSelect } from "@/composables/useMarqueeSelect";
import UploadZone from "@/components/files/UploadZone.vue";
import FilterBar from "@/components/files/FilterBar.vue";
import FilePreview from "@/components/files/FilePreview.vue";
import FileDetails from "@/components/files/FileDetails.vue";
import PhotoPlacePicker from "@/components/files/PhotoPlacePicker.vue";
import AlbumPicker from "@/components/files/AlbumPicker.vue";
import ShareModal from "@/components/files/ShareModal.vue";
import ContextMenu from "@/components/ui/ContextMenu.vue";
import BulkActionBar from "@/components/ui/BulkActionBar.vue";
import PhotoTimeline from "@/components/files/PhotoTimeline.vue";
import { formatFileSize, formatRelativeDate, groupByDate } from "@/utils/formatting";
import api from "@/api/client";

const auth = useAuthStore();
const filesStore = useFilesStore();
const vault = useVaultStore();
const vaultGate = useVaultGate();
const privateDest = usePrivateDestination();
const {
  count: selectedCount,
  hasSelection,
  isSelected,
  clear: clearSelection,
  onSelect,
  selectAll,
  selectMany,
  selectedOf,
} = useSelection();
const contextMenu = useContextMenu();
/** The photograph having its place set, if any. */
const placingFile = ref(null);

/**
 * Albums — folders of their own, which never appear in My Files.
 *
 * Everything in one grid stops being a gallery somewhere around the second
 * year. The default album is where photographs live until somebody files them
 * somewhere better, and it is what opens.
 */
const albums = ref([]);
const albumId = ref(null);
/** Photographs waiting to be filed, while the album picker is open. */
const filing = ref(null);
/** Which bulk action is actually running, so only that button spins. */
const runningAction = ref("");

const currentAlbum = computed(() => albums.value.find((a) => a.id === albumId.value) ?? null);
const defaultAlbum = computed(() => albums.value.find((a) => a.is_default) ?? null);

async function loadAlbums() {
  try {
    const { data } = await api.get("/folders", { params: { kind: "photo" } });
    albums.value = data.folders;
    if (albumId.value === null) {
      albumId.value = (data.folders.find((f) => f.is_default) ?? data.folders[0])?.id ?? null;
    }
  } catch {
    // Without albums the gallery is what it always was: one grid.
  }
}

async function openAlbum(id) {
  albumId.value = id;
  await load();
}

async function newAlbum() {
  const name = await dialog.prompt({
    title: "New album",
    label: "What is it called?",
    placeholder: "Cornwall 2025",
    confirmLabel: "Create",
  });
  if (!name?.trim()) return;

  try {
    await api.post("/folders", { folder: { name: name.trim(), kind: "photo" } });
    await loadAlbums();
  } catch (e) {
    toast.show({ message: e.userMessage });
  }
}

/** Files the selected photographs under an album. */
async function moveToAlbum(photos, targetId) {
  try {
    for (const photo of photos) {
      await api.patch(`/files/${photo.id}`, { folder_id: targetId });
    }
    await load();
    await loadAlbums();
  } catch (e) {
    toast.show({ message: e.userMessage });
  }
}
const dialog = useDialog();
const toast = useToast();
const bulkBusy = ref(false);

const galleryRoot = ref(null);
// Snapshot of the selection when a Ctrl/Cmd-marquee starts, so tiles that leave
// the rectangle are not left selected forever.
const marqueeBaseline = ref(null);

function onMarqueeIds(ids, { additive }) {
  if (additive) {
    if (!marqueeBaseline.value) {
      marqueeBaseline.value = new Set(selectedOf("file").map(String));
    }
    const merged = new Set(marqueeBaseline.value);
    for (const id of ids) merged.add(String(id));
    selectMany([...merged].map((id) => ({ type: "file", id })), { additive: false });
    return;
  }

  marqueeBaseline.value = null;
  selectMany(
    ids.map((id) => ({ type: "file", id })),
    { additive: false },
  );
}

const { box: marqueeBox, onPointerDown: onMarqueePointerDown } = useMarqueeSelect({
  rootRef: galleryRoot,
  onSelect: onMarqueeIds,
});

function onMarqueeDown(event) {
  marqueeBaseline.value = null;
  onMarqueePointerDown(event);
}

const visibility = ref("private");

const TILE_KEY = "cloudvault.gallery.tileSize";
const TILE_SIZES = {
  sm: { label: "S", grid: "grid-cols-3 md:grid-cols-5 lg:grid-cols-8", gap: "gap-1.5" },
  md: { label: "M", grid: "grid-cols-2 md:grid-cols-4 lg:grid-cols-6", gap: "gap-3" },
  lg: { label: "L", grid: "grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4", gap: "gap-4" },
};

const tileSize = ref(
  TILE_SIZES[localStorage.getItem(TILE_KEY)] ? localStorage.getItem(TILE_KEY) : "md",
);
const tile = computed(() => TILE_SIZES[tileSize.value] ?? TILE_SIZES.md);

function setTileSize(size) {
  if (!TILE_SIZES[size]) return;
  tileSize.value = size;
  localStorage.setItem(TILE_KEY, size);
}

const filters = ref({
  // Capture date is what a photo timeline is about.
  sort: "taken_newest",
  owner_id: "",
  visibility: "",
  orientation: "",
  has_location: "",
  // Where somebody said it was taken, which is the only place most of the
  // gallery will ever know.
  place: "",
  date_from: "",
  date_to: "",
  label_ids: [],
});
const previewFile = ref(null);
const detailsFile = ref(null);
const sharingFile = ref(null);
/** Photo ids whose thumb URL failed after a retry (expired / corrupt). */
const broken = ref(new Set());
/** How many times we asked the API to rebuild a missing/broken thumb. */
const thumbAttempts = ref(new Map());
let thumbRefreshTimer = null;

// Sentinel at the bottom of the grid; when it scrolls into view, load the next
// page (PATTERNS.md §Image Gallery with Infinite Scroll).
const sentinel = ref(null);
let observer = null;

function captureDate(photo) {
  return photo.captured_at || photo.image?.taken_at || photo.created_at;
}

function dayKey(photo) {
  const raw = captureDate(photo);
  if (!raw) return "undated";
  const d = new Date(raw);
  if (Number.isNaN(d.getTime())) return "undated";
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function jumpToMonth({ year, month }) {
  const match = filesStore.items.find((photo) => {
    const raw = captureDate(photo);
    if (!raw) return false;
    const d = new Date(raw);
    return d.getFullYear() === year && d.getMonth() === month;
  });
  if (!match) return;

  const el = document.getElementById(`timeline-${dayKey(match)}`);
  el?.scrollIntoView({ behavior: "smooth", block: "start" });
}

// Day-level sections, keyed by when the photo was taken (falling back to upload).
const groups = computed(() => groupByDate(filesStore.items, captureDate));
const showEmpty = computed(() => !filesStore.loading && filesStore.items.length === 0);

const hasFilters = computed(() => {
  const f = filters.value;
  return Boolean(
    f.owner_id || f.visibility || f.orientation || f.has_location || f.place ||
    f.date_from || f.date_to || f.label_ids.length,
  );
});

const selectableItems = computed(() =>
  filesStore.items.map((file) => ({ type: "file", id: file.id })),
);

const bulkActions = computed(() => [
  {
    id: "download",
    label: selectedCount.value > 1 ? "Download ZIP" : "Download",
    icon: selectedCount.value > 1 ? "fa-file-zipper" : "fa-download",
  },
  { id: "album", label: "Put in an album…", icon: "fa-folder" },
  { id: "document", label: "These aren't photos", icon: "fa-file-lines" },
  vault.exists && { id: "private", label: "Move to Private", icon: "fa-lock" },
  { id: "trash", label: "Move to trash", icon: "fa-trash", danger: true },
].filter(Boolean));

function onEscape(event) {
  if (event.key === "Escape" && hasSelection.value) clearSelection();
}

function onKeySelectAll(event) {
  if (!(event.metaKey || event.ctrlKey) || event.key !== "a") return;
  // Don't steal Ctrl+A from inputs.
  if (event.target.closest("input, textarea, [contenteditable]")) return;
  event.preventDefault();
  selectAll(selectableItems.value);
}

onMounted(async () => {
  window.addEventListener("keydown", onEscape);
  window.addEventListener("keydown", onKeySelectAll);
  // Albums first: which one is open decides what the grid asks for.
  await loadAlbums();
  load();

  observer = new IntersectionObserver(
    (entries) => {
      if (!entries[0]?.isIntersecting) return;
      filesStore.loadMore().then(() => scheduleThumbRefresh());
    },
    // Start fetching slightly before the sentinel is actually visible.
    { rootMargin: "300px" },
  );
});

// The sentinel only exists once results have rendered.
watch(sentinel, (el, previous) => {
  if (previous) observer?.unobserve(previous);
  if (el) observer?.observe(el);
});

onBeforeUnmount(() => {
  window.removeEventListener("keydown", onEscape);
  window.removeEventListener("keydown", onKeySelectAll);
  observer?.disconnect();
  clearTimeout(thumbRefreshTimer);
});

// Remembered from the last unfiltered load so the header can say "8 of 27".
const unfilteredTotal = ref(0);

async function load() {
  const { label_ids: labelIds, ...rest } = filters.value;
  // An album is a folder, and the grid shows one at a time.
  if (albumId.value != null) rest.folder_id = albumId.value;
  await filesStore.fetchFiles({ fileType: "image", labelIds, filters: rest });

  if (!hasFilters.value) unfilteredTotal.value = filesStore.totalCount;
  scheduleThumbRefresh();
}

/** Pictures whose job has not finished yet — ask again shortly. */
function scheduleThumbRefresh() {
  clearTimeout(thumbRefreshTimer);
  const missing = filesStore.items.filter(
    (photo) => !photo.image?.thumbnail_url && !broken.value.has(photo.id),
  );
  if (!missing.length) return;

  const queue = missing.filter((photo) => (thumbAttempts.value.get(photo.id) || 0) < 3);
  if (!queue.length) return;

  thumbRefreshTimer = setTimeout(async () => {
    const batch = queue.slice(0, 40);
    const reprocessResults = await Promise.allSettled(
      batch.map((photo) => api.post(`/files/${photo.id}/reprocess`)),
    );

    // A rate-limited attempt never got a real chance, so it shouldn't count
    // against the photo's 3-try budget — only charge the ones that actually ran.
    let rateLimited = false;
    batch.forEach((photo, i) => {
      if (reprocessResults[i].status === "rejected" && reprocessResults[i].reason?.status === 429) {
        rateLimited = true;
        return;
      }
      thumbAttempts.value.set(photo.id, (thumbAttempts.value.get(photo.id) || 0) + 1);
    });

    // Rate-limited: every other request in this round almost certainly is too.
    // Back off hard instead of retrying every few seconds and digging the same
    // hole deeper — a large batch upload is exactly when this loop runs widest.
    if (rateLimited) {
      thumbRefreshTimer = setTimeout(scheduleThumbRefresh, 30_000);
      return;
    }

    // Pull fresh thumbnail_url for each without resetting infinite scroll.
    setTimeout(async () => {
      await Promise.allSettled(
        batch.map(async (photo) => {
          const { data } = await api.get(`/files/${photo.id}`);
          filesStore.upsertFile(data.file);
        }),
      );
      scheduleThumbRefresh();
    }, 3000);
  }, 1500);
}

/** Expired MinIO URL or a thumb that never attached — retry once, then give up. */
function onThumbError(photo) {
  const tries = thumbAttempts.value.get(photo.id) || 0;
  if (tries < 2) {
    thumbAttempts.value.set(photo.id, tries + 1);
    api.post(`/files/${photo.id}/reprocess`).catch(() => null);
    setTimeout(async () => {
      try {
        const { data } = await api.get(`/files/${photo.id}`);
        filesStore.upsertFile(data.file);
      } catch {
        /* ignore */
      }
      scheduleThumbRefresh();
    }, 2000);
    return;
  }
  // New Set so Vue notices the change (mutating .add on a ref Set does not).
  broken.value = new Set([...broken.value, photo.id]);
}

// Sorting by anything but date makes the date headings meaningless.
const grouped = computed(() =>
  ["newest", "oldest", "taken_newest", "taken_oldest"].includes(filters.value.sort),
);

async function onTrash(file) {
  const ok = await dialog.confirm({
    title: `Move "${file.name}" to trash?`,
    message: "You can restore it from Trash for 30 days.",
    confirmLabel: "Move to trash",
    danger: true,
  });
  if (!ok) return;

  await filesStore.trash(file);
  clearSelection();
}

async function onDownload(file) {
  try {
    await filesStore.download(file);
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

/**
 * Certificates, receipts and forms get photographed, and then live in the photo
 * gallery among the birthdays. This moves one to My Files without touching the
 * file itself.
 */
async function fileAsDocument(file) {
  try {
    await filesStore.setFileType(file, "file");

    toast.show({
      message: "Moved to My Files",
      detail: file.name,
      actionLabel: "Undo",
      action: async () => {
        await filesStore.setFileType(file, "image");
        load();
      },
    });
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

async function movePhotoToPrivate(file) {
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

function onUploadComplete({ uploaded, failed }) {
  load();
  clearSelection();

  if (!uploaded.length) {
    if (failed) toast.show({ message: "Upload failed", tone: "error" });
    return;
  }

  toast.show({
    message: uploaded.length === 1 ? "Photo uploaded" : `Uploaded ${uploaded.length} photos`,
    detail: failed ? `${failed} failed` : (uploaded.length === 1 ? uploaded[0].name : ""),
  });
}

function selectPhoto(event, file) {
  onSelect("file", file.id, event, selectableItems.value);
}

function selectDay(photos) {
  selectMany(
    photos.map((photo) => ({ type: "file", id: photo.id })),
    { additive: true },
  );
}

function selectAllLoaded() {
  selectAll(selectableItems.value);
}

function onPhotoClick(event, file) {
  if (event.metaKey || event.ctrlKey || event.shiftKey || hasSelection.value) {
    selectPhoto(event, file);
    return;
  }
  previewFile.value = file;
}

/** Filing whatever the picker was opened for, into an album that exists. */
async function fileInto(targetId) {
  const photos = filing.value ?? [];
  filing.value = null;
  if (!photos.length) return;

  await moveToAlbum(photos, targetId);
  toast.show({ message: `${photos.length} filed` });
  clearSelection();
}

/** …or into one that does not exist yet. */
async function fileIntoNew(name) {
  try {
    const { data } = await api.post("/folders", { folder: { name, kind: "photo" } });
    await loadAlbums();
    await fileInto(data.folder.id);
  } catch (e) {
    filing.value = null;
    toast.show({ message: e.userMessage });
  }
}

/** Renaming and removing an album, from the chip itself. */
async function renameAlbum(album) {
  const name = await dialog.prompt({
    title: "Rename album", label: "What should it be called?",
    value: album.name, confirmLabel: "Rename",
  });
  if (!name?.trim() || name.trim() === album.name) return;

  try {
    await api.patch(`/folders/${album.id}`, { folder: { name: name.trim() } });
    await loadAlbums();
  } catch (e) {
    toast.show({ message: e.userMessage });
  }
}

async function deleteAlbum(album) {
  const ok = await dialog.confirm({
    title: `Remove the album “${album.name}”?`,
    message: "The album goes; the photographs in it do not.",
    detail: `They go back to ${defaultAlbum.value?.name ?? "the default album"}.`,
    confirmLabel: "Remove the album",
    danger: true,
  });
  if (!ok) return;

  try {
    await api.delete(`/folders/${album.id}`);
    if (albumId.value === album.id) albumId.value = defaultAlbum.value?.id ?? null;
    await loadAlbums();
    await load();
  } catch (e) {
    toast.show({ message: e.userMessage });
  }
}

function albumMenu(event, album) {
  if (album.is_default) return;

  contextMenu.open(event, {
    items: [
      { label: "Rename", icon: "fa-pen", action: () => renameAlbum(album) },
      {
        label: "Remove the album", icon: "fa-trash", danger: true,
        action: () => deleteAlbum(album),
      },
    ],
  });
}

function onPlaceSaved(updated) {
  const index = filesStore.items.findIndex((f) => f.id === updated.id);
  if (index >= 0) filesStore.items.splice(index, 1, updated);
  if (detailsFile.value?.id === updated.id) detailsFile.value = updated;
}

function selectedPhotos() {
  return selectedOf("file")
    .map((id) => filesStore.items.find((f) => String(f.id) === String(id)))
    .filter(Boolean);
}

async function runBulk(actionId) {
  if (bulkBusy.value) return;
  const photos = selectedPhotos();
  if (!photos.length) return;

  bulkBusy.value = true;
  runningAction.value = actionId;
  try {
    if (actionId === "download") {
      if (photos.length === 1) {
        await filesStore.download(photos[0]);
      } else {
        await filesStore.downloadZip(photos.map((p) => p.id));
        toast.show({ message: `Downloading ${photos.length} photos as ZIP` });
      }
    } else if (actionId === "album") {
      filing.value = photos;
    } else if (actionId === "document") {
      // This takes them out of the gallery altogether, which is not what
      // "move to My Files" sounded like to the person who pressed it.
      const ok = await dialog.confirm({
        title: `Treat ${photos.length} ${photos.length === 1 ? "photo" : "photos"} as documents?`,
        message:
          "They leave the gallery and appear in My Files instead — for pictures of paperwork " +
          "rather than pictures of people.",
        detail: "Nothing is deleted. You can send them back from My Files at any time.",
        confirmLabel: "Move them",
      });
      if (!ok) return;

      for (const photo of photos) {
        await filesStore.setFileType(photo, "file");
      }
      toast.show({
        message: `Moved ${photos.length} to My Files`,
        detail: "Find them under My Files, not in an album.",
      });
      clearSelection();
      await load();
      await loadAlbums();
    } else if (actionId === "private") {
      if (!(await vaultGate.ensureUnlocked())) return;

      const folderId = await privateDest.pick({
        title: `Move ${photos.length} ${photos.length === 1 ? "photo" : "photos"} to Private`,
      });
      if (folderId === undefined) return;

      for (const photo of photos) {
        await filesStore.moveToPrivate(photo, folderId);
      }
      toast.show({
        message: `Moved ${photos.length} ${photos.length === 1 ? "photo" : "photos"} to Private`,
      });
      clearSelection();
    } else if (actionId === "trash") {
      const ok = await dialog.confirm({
        title: `Move ${photos.length} ${photos.length === 1 ? "photo" : "photos"} to trash?`,
        message: "You can restore them from Trash for 30 days.",
        confirmLabel: "Move to trash",
        danger: true,
      });
      if (!ok) return;

      for (const photo of photos) {
        await filesStore.trash(photo);
      }
      toast.show({
        message: `Moved ${photos.length} ${photos.length === 1 ? "photo" : "photos"} to trash`,
      });
      clearSelection();
    }
  } catch (e) {
    filesStore.error = e.userMessage;
  } finally {
    bulkBusy.value = false;
    runningAction.value = "";
  }
}

function photoMenu(event, file) {
  if (selectedCount.value > 1 && isSelected("file", file.id)) {
    contextMenu.open(event, {
      title: `${selectedCount.value} selected`,
      items: [
        { label: "Download as ZIP", icon: "fa-file-zipper", action: () => runBulk("download") },
        // The same three moves the bar offers, in the same words. Two menus
        // over the same selection saying different things is how somebody ends
        // up pressing the one they did not mean.
        { label: "Put in an album…", icon: "fa-folder", action: () => runBulk("album") },
        { label: "These aren't photos", icon: "fa-file-lines", action: () => runBulk("document") },
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
      {
        // Almost no photograph arrives knowing where it was taken, so this is
        // the only way the gallery will ever be searchable by place.
        label: file.image?.place_name ? "Change the place" : "Say where it was taken",
        icon: "fa-location-dot",
        action: () => (placingFile.value = file),
      },
      {
        label: "Move to an album…",
        icon: "fa-folder",
        action: () => (filing.value = [ file ]),
      },
      file.permissions.can_share && {
        label: "Share…", icon: "fa-share-nodes", action: () => (sharingFile.value = file),
      },
      file.permissions.can_edit && { divider: true },
      file.permissions.can_edit && {
        label: "This is a document",
        icon: "fa-file-lines",
        action: () => fileAsDocument(file),
      },
      file.permissions.can_edit && vault.exists && {
        label: "Move to Private",
        icon: "fa-lock",
        action: () => movePhotoToPrivate(file),
      },
      file.permissions.can_delete && { divider: true },
      file.permissions.can_delete && {
        label: "Move to trash", icon: "fa-trash", danger: true, action: () => onTrash(file),
      },
    ],
  });
}
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-center justify-between gap-4">
      <div>
        <h1 class="text-h2 font-bold text-gray-800">
          {{ currentAlbum ? currentAlbum.name : "Photo Gallery" }}
        </h1>
        <p class="mt-1 text-body-sm text-gray-500">
          <template v-if="hasFilters">
            {{ filesStore.totalCount }} of {{ unfilteredTotal }}
            {{ unfilteredTotal === 1 ? "photo" : "photos" }} match
          </template>
          <template v-else>
            {{ filesStore.totalCount }} {{ filesStore.totalCount === 1 ? "photo" : "photos" }}
          </template>
          <span v-if="filesStore.items.length < filesStore.totalCount" class="text-gray-400">
            · showing {{ filesStore.items.length }}, scroll for more
          </span>
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <div
          class="flex items-center rounded-base border border-gray-300 p-0.5"
          role="group"
          aria-label="Thumbnail size"
        >
          <button
            v-for="(cfg, key) in TILE_SIZES"
            :key="key"
            type="button"
            :aria-pressed="tileSize === key"
            :class="[
              'rounded px-2.5 py-1.5 text-caption font-semibold transition',
              tileSize === key
                ? 'bg-primary-600 text-white'
                : 'text-gray-600 hover:bg-gray-50',
            ]"
            @click="setTileSize(key)"
          >
            {{ cfg.label }}
          </button>
        </div>

        <label for="photo-visibility" class="sr-only">Upload visibility</label>
        <select
          id="photo-visibility"
          v-model="visibility"
          class="rounded-base border border-gray-300 px-3 py-2 text-body outline-none focus:ring-2 focus:ring-primary-500"
        >
          <option value="private">Only me</option>
          <option value="family" :disabled="!auth.canEdit">Share with family</option>
        </select>
      </div>
    </header>

    <!--
      image/* alone hides .heic and .avif in the file picker on systems that do
      not register them as image types, so the extensions are listed too.
    -->
    <UploadZone
      :visibility="visibility"
      accept="image/*,.heic,.heif,.avif,.jxl"
      class="mb-6"
      @complete="onUploadComplete"
    />

    <!-- Albums. One grid holding everything stops being a gallery somewhere
         around the second year, so the default album is what opens and the
         rest are a click away. -->
    <div v-if="albums.length" class="mb-5 flex flex-wrap items-center gap-2">
      <button
        v-for="album in albums"
        :key="album.id"
        type="button"
        :aria-pressed="album.id === albumId"
        :class="[
          'flex items-center gap-2 rounded-full border px-3 py-1.5 text-body-sm font-medium transition',
          album.id === albumId
            ? 'border-primary-600 bg-primary-50 text-primary-700'
            : 'border-gray-200 bg-white text-gray-600 hover:border-gray-300',
        ]"
        :title="album.is_default ? album.name : `${album.name} — right-click to rename or remove`"
        @click="openAlbum(album.id)"
        @contextmenu.prevent="albumMenu($event, album)"
      >
        <i :class="['fas', album.is_default ? 'fa-images' : 'fa-folder']" aria-hidden="true"></i>
        {{ album.name }}
        <span class="tabular-nums opacity-60">{{ album.file_count }}</span>
      </button>

      <button
        type="button"
        class="rounded-full border border-dashed border-gray-300 px-3 py-1.5 text-body-sm font-medium text-gray-500 transition hover:border-gray-400 hover:text-gray-700"
        @click="newAlbum"
      >
        <i class="fas fa-plus mr-1.5" aria-hidden="true"></i>New album
      </button>
    </div>

    <FilterBar v-model="filters" photo-filters capture-sort @change="load" />

    <p
      v-if="filesStore.error"
      role="alert"
      class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
    >
      {{ filesStore.error }}
    </p>

    <!-- First load -->
    <div v-if="filesStore.loading" :class="['grid', tile.grid, tile.gap]">
      <div v-for="n in 12" :key="n" class="aspect-square animate-pulse rounded-lg bg-gray-100"></div>
    </div>

    <div v-else-if="showEmpty" class="rounded-lg border border-gray-200 bg-white p-12 text-center">
      <i class="fas fa-images text-4xl text-gray-300" aria-hidden="true"></i>
      <h2 class="mt-4 text-h3 font-semibold text-gray-800">
        {{ hasFilters ? "No photos match those filters" : "No photos yet" }}
      </h2>
      <p class="mt-2 text-body text-gray-500">
        {{ hasFilters ? "Try widening the date range or clearing a filter." : "Drop images above and they'll appear here." }}
      </p>
    </div>

    <template v-else>
      <div class="mb-3 flex flex-wrap items-center justify-between gap-2 text-body-sm text-gray-500">
        <p>
          Drag across photos to select · Shift-click a range · Ctrl/Cmd-click to toggle ·
          Ctrl/Cmd+A for all loaded
        </p>
        <button
          type="button"
          class="rounded-base border border-gray-300 px-3 py-1.5 font-medium text-gray-700 transition hover:bg-gray-50"
          @click="selectAllLoaded"
        >
          Select all loaded ({{ filesStore.items.length }})
        </button>
      </div>

      <PhotoTimeline
        :photos="filesStore.items"
        :capture-date="captureDate"
        @jump="jumpToMonth"
      />

      <div
        ref="galleryRoot"
        class="relative select-none"
        @pointerdown="onMarqueeDown"
      >
        <div
          v-if="marqueeBox"
          class="pointer-events-none absolute z-30 border-2 border-primary-500 bg-primary-500/15"
          :style="{
            left: `${marqueeBox.x}px`,
            top: `${marqueeBox.y}px`,
            width: `${marqueeBox.w}px`,
            height: `${marqueeBox.h}px`,
          }"
        ></div>

        <section
          v-for="group in (grouped ? groups : [{ label: null, items: filesStore.items }])"
          :key="group.label ?? 'all'"
          :id="group.items[0] ? `timeline-${dayKey(group.items[0])}` : undefined"
          class="mb-8 scroll-mt-4"
        >
          <div
            v-if="group.label"
            class="sticky top-0 z-10 -mx-1 mb-3 flex items-center justify-between gap-3 bg-gray-50/95 px-1 py-2 backdrop-blur"
          >
            <h2 class="text-body font-semibold text-gray-800">
              {{ group.label }}
              <span class="ml-2 text-caption font-normal text-gray-400">{{ group.items.length }}</span>
            </h2>
            <button
              type="button"
              class="shrink-0 text-caption font-medium text-primary-600 hover:underline"
              @click.stop="selectDay(group.items)"
            >
              Select day
            </button>
          </div>

          <ul :class="['grid', tile.grid, tile.gap]">
            <li
              v-for="photo in group.items"
              :key="photo.id"
              :data-marquee-id="photo.id"
            >
              <div
                :class="[
                  'group relative aspect-square w-full overflow-hidden rounded-lg bg-gray-100',
                  isSelected('file', photo.id) ? 'ring-2 ring-primary-500 ring-offset-2' : '',
                ]"
                @contextmenu="photoMenu($event, photo)"
              >
                <button
                  type="button"
                  data-select-toggle
                  :class="[
                    'absolute left-2 top-2 z-10 flex h-5 w-5 items-center justify-center rounded border transition',
                    isSelected('file', photo.id)
                      ? 'border-primary-600 bg-primary-600 text-white opacity-100'
                      : 'border-white/80 bg-black/30 text-transparent opacity-0 group-hover:opacity-100',
                    hasSelection ? 'opacity-100' : '',
                  ]"
                  :aria-label="isSelected('file', photo.id) ? `Deselect ${photo.name}` : `Select ${photo.name}`"
                  :aria-pressed="isSelected('file', photo.id)"
                  @click="selectPhoto($event, photo)"
                >
                  <i class="fas fa-check text-[10px]" aria-hidden="true"></i>
                </button>

                <button
                  type="button"
                  class="absolute inset-0 block w-full focus-visible:ring-2 focus-visible:ring-primary-500"
                  :aria-label="`Open ${photo.name}`"
                  @click="onPhotoClick($event, photo)"
                >
                  <img
                    v-if="photo.image?.thumbnail_url && !broken.has(photo.id)"
                    :src="photo.image.thumbnail_url"
                    :alt="photo.name"
                    loading="lazy"
                    draggable="false"
                    class="h-full w-full object-cover transition-transform duration-200 group-hover:scale-105"
                    @error="onThumbError(photo)"
                  />
                  <span v-else class="flex h-full w-full items-center justify-center text-gray-300">
                    <i class="fas fa-image text-2xl" aria-hidden="true"></i>
                  </span>

                  <span
                    class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-gray-900/80 to-transparent p-2 text-left opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100"
                  >
                    <span class="block truncate text-caption font-medium text-white">{{ photo.name }}</span>
                    <span class="block text-caption text-gray-300">
                      {{ formatRelativeDate(captureDate(photo)) }} ·
                      {{ formatFileSize(photo.size) }}
                      <i
                        v-if="photo.image?.location"
                        class="fas fa-location-dot ml-1"
                        :title="'Has location'"
                        aria-hidden="true"
                      ></i>
                    </span>
                  </span>

                  <span
                    v-if="photo.visibility === 'family'"
                    class="absolute right-2 top-2 rounded-full bg-white/90 px-2 py-0.5 text-caption font-medium text-primary-700"
                  >
                    <i class="fas fa-users" aria-hidden="true"></i>
                  </span>
                </button>
              </div>
            </li>
          </ul>
        </section>

        <!-- Infinite scroll sentinel + skeletons while the next page loads -->
        <div v-if="filesStore.hasMore" ref="sentinel" class="pb-8">
          <div v-if="filesStore.loadingMore" :class="['grid', tile.grid, tile.gap]">
            <div v-for="n in 6" :key="n" class="aspect-square animate-pulse rounded-lg bg-gray-100"></div>
          </div>
          <p v-else class="text-center text-caption text-gray-400">More photos loading…</p>
        </div>
      </div>

      <BulkActionBar
        v-if="hasSelection"
        :count="selectedCount"
        noun="photo"
        :actions="bulkActions"
        :busy="bulkBusy"
        :running="runningAction"
        @action="runBulk"
        @clear="clearSelection"
      />
    </template>

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

    <AlbumPicker
      v-if="filing"
      :albums="albums"
      :count="filing.length"
      :current-id="filing.length === 1 ? (filing[0]?.folder_id ?? null) : null"
      @choose="fileInto"
      @create="fileIntoNew"
      @close="filing = null"
    />

    <PhotoPlacePicker
      v-if="placingFile"
      :file="placingFile"
      @saved="onPlaceSaved"
      @close="placingFile = null"
    />
  </section>
</template>
