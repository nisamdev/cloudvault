<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { useAuthStore } from "@/stores/auth";
import { useFilesStore } from "@/stores/files";
import { useContextMenu } from "@/composables/useContextMenu";
import { useDialog } from "@/composables/useDialog";
import UploadZone from "@/components/files/UploadZone.vue";
import GalleryFilters from "@/components/files/GalleryFilters.vue";
import FilePreview from "@/components/files/FilePreview.vue";
import FileDetails from "@/components/files/FileDetails.vue";
import ShareModal from "@/components/files/ShareModal.vue";
import ContextMenu from "@/components/ui/ContextMenu.vue";
import { formatFileSize, formatRelativeDate, groupByDate } from "@/utils/formatting";

const auth = useAuthStore();
const filesStore = useFilesStore();
const contextMenu = useContextMenu();
const dialog = useDialog();

const visibility = ref("private");

const filters = ref({
  sort: "newest",
  owner_id: "",
  visibility: "",
  orientation: "",
  has_location: "",
  date_from: "",
  date_to: "",
  label_ids: [],
});
const previewFile = ref(null);
const detailsFile = ref(null);
const sharingFile = ref(null);
const broken = ref(new Set());

// Sentinel at the bottom of the grid; when it scrolls into view, load the next
// page (PATTERNS.md §Image Gallery with Infinite Scroll).
const sentinel = ref(null);
let observer = null;

// Grouped by upload date so the headings agree with the date filters. Capture
// date is shown in the details panel and available as an explicit sort.
const groups = computed(() => groupByDate(filesStore.items, "created_at"));
const showEmpty = computed(() => !filesStore.loading && filesStore.items.length === 0);

const hasFilters = computed(() => {
  const f = filters.value;
  return Boolean(
    f.owner_id || f.visibility || f.orientation || f.has_location ||
    f.date_from || f.date_to || f.label_ids.length,
  );
});

onMounted(() => {
  load();

  observer = new IntersectionObserver(
    (entries) => {
      if (entries[0]?.isIntersecting) filesStore.loadMore();
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

onBeforeUnmount(() => observer?.disconnect());

// Remembered from the last unfiltered load so the header can say "8 of 27".
const unfilteredTotal = ref(0);

async function load() {
  const { label_ids: labelIds, ...rest } = filters.value;
  await filesStore.fetchFiles({ fileType: "image", labelIds, filters: rest });

  if (!hasFilters.value) unfilteredTotal.value = filesStore.totalCount;
}

// Sorting by anything but date makes the date headings meaningless.
const grouped = computed(() => filters.value.sort === "newest" || filters.value.sort === "oldest");

async function onTrash(file) {
  const ok = await dialog.confirm({
    title: `Move "${file.name}" to trash?`,
    message: "You can restore it from Trash for 30 days.",
    confirmLabel: "Move to trash",
    danger: true,
  });
  if (!ok) return;

  await filesStore.trash(file);
}

async function onDownload(file) {
  try {
    await filesStore.download(file);
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

function photoMenu(event, file) {
  contextMenu.open(event, {
    title: file.name,
    items: [
      { label: "Preview", icon: "fa-eye", action: () => (previewFile.value = file) },
      { label: "Download", icon: "fa-download", action: () => onDownload(file) },
      { label: "Details", icon: "fa-circle-info", action: () => (detailsFile.value = file) },
      file.permissions.can_share && {
        label: "Share…", icon: "fa-share-nodes", action: () => (sharingFile.value = file),
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
        <h1 class="text-h2 font-bold text-gray-800">Photo Gallery</h1>
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

      <div>
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

    <UploadZone :visibility="visibility" accept="image/*" class="mb-6" @uploaded="load" />

    <GalleryFilters v-model="filters" @change="load" />

    <p
      v-if="filesStore.error"
      role="alert"
      class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
    >
      {{ filesStore.error }}
    </p>

    <!-- First load -->
    <div v-if="filesStore.loading" class="grid grid-cols-2 gap-3 md:grid-cols-4 lg:grid-cols-6">
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
      <section
        v-for="group in (grouped ? groups : [{ label: null, items: filesStore.items }])"
        :key="group.label ?? 'all'"
        class="mb-8"
      >
        <h2
          v-if="group.label"
          class="mb-3 text-label font-medium uppercase tracking-wide text-gray-500"
        >
          {{ group.label }}
        </h2>

        <ul class="grid grid-cols-2 gap-3 md:grid-cols-4 lg:grid-cols-6">
          <li v-for="photo in group.items" :key="photo.id">
            <button
              type="button"
              class="group relative block aspect-square w-full overflow-hidden rounded-lg bg-gray-100 focus-visible:ring-2 focus-visible:ring-primary-500"
              @click="previewFile = photo"
              @contextmenu="photoMenu($event, photo)"
            >
              <img
                v-if="photo.image?.thumbnail_url && !broken.has(photo.id)"
                :src="photo.image.thumbnail_url"
                :alt="photo.name"
                loading="lazy"
                class="h-full w-full object-cover transition-transform duration-200 group-hover:scale-105"
                @error="broken.add(photo.id)"
              />
              <!-- No thumbnail yet: the job runs a moment after upload. -->
              <span v-else class="flex h-full w-full items-center justify-center text-gray-300">
                <i class="fas fa-image text-2xl" aria-hidden="true"></i>
              </span>

              <!-- Hover overlay with the date (PATTERNS.md) -->
              <span
                class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-gray-900/80 to-transparent p-2 text-left opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100"
              >
                <span class="block truncate text-caption font-medium text-white">{{ photo.name }}</span>
                <span class="block text-caption text-gray-300">
                  {{ formatRelativeDate(photo.created_at) }} ·
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
          </li>
        </ul>
      </section>

      <!-- Infinite scroll sentinel + skeletons while the next page loads -->
      <div v-if="filesStore.hasMore" ref="sentinel" class="pb-8">
        <div v-if="filesStore.loadingMore" class="grid grid-cols-2 gap-3 md:grid-cols-4 lg:grid-cols-6">
          <div v-for="n in 6" :key="n" class="aspect-square animate-pulse rounded-lg bg-gray-100"></div>
        </div>
        <p v-else class="text-center text-caption text-gray-400">More photos loading…</p>
      </div>
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
  </section>
</template>
