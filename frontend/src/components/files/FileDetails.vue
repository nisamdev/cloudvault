<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from "vue";
import api from "@/api/client";
import { formatFileSize, fileIcon } from "@/utils/formatting";

const props = defineProps({
  file: { type: Object, required: true },
});
const emit = defineEmits(["close"]);

const details = ref(null);
const versions = ref([]);
const loading = ref(true);
const error = ref("");
const panel = ref(null);
const closeButton = ref(null);
let previouslyFocused = null;

const image = computed(() => details.value?.image);
const location = computed(() => image.value?.location);

const mapUrl = computed(() => {
  if (!location.value) return null;
  const { latitude: lat, longitude: lon } = location.value;
  return `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}#map=15/${lat}/${lon}`;
});

/** Full timestamp — the details panel is exactly where "3 days ago" is unhelpful. */
function fullDate(value) {
  if (!value) return null;
  return new Date(value).toLocaleString(undefined, {
    weekday: "short",
    day: "numeric",
    month: "long",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

// Only rows with a value are rendered, so the panel never shows a wall of "—".
const dateRows = computed(() => {
  const d = details.value;
  if (!d) return [];

  return [
    { label: "Uploaded", value: fullDate(d.uploaded_at) },
    { label: "Taken", value: fullDate(d.taken_at), hint: "from the photo's EXIF data" },
    { label: "Last modified", value: fullDate(d.updated_at) },
    { label: "Last opened", value: fullDate(d.last_accessed_at) },
    { label: "Moved to trash", value: fullDate(d.trashed_at) },
    { label: "Deletes permanently", value: fullDate(d.purge_after) },
  ].filter((row) => row.value);
});

const fileRows = computed(() => {
  const d = details.value;
  if (!d) return [];

  return [
    { label: "Type", value: d.mime_type },
    { label: "Size", value: formatFileSize(d.size) },
    {
      label: "Dimensions",
      value: image.value?.width ? `${image.value.width} × ${image.value.height}px` : null,
    },
    { label: "Megapixels", value: image.value?.megapixels ? `${image.value.megapixels} MP` : null },
    { label: "Camera", value: image.value?.camera },
    { label: "Owner", value: d.owner?.name },
    { label: "Folder", value: d.folder?.path ?? "Top level" },
    { label: "Family", value: d.family?.name },
    {
      label: "Visibility",
      value: d.visibility === "family" ? "Shared with family" : "Only me",
    },
    { label: "Version", value: d.version_number > 1 ? `v${d.version_number}` : null },
    {
      label: "Earlier versions",
      value: d.version_count ? `${d.version_count} kept` : null,
    },
    {
      label: "Public links",
      value: d.active_share_links ? `${d.active_share_links} active` : null,
    },
    { label: "Checksum", value: d.checksum, mono: true },
  ].filter((row) => row.value);
});

function onKeydown(event) {
  if (event.key === "Escape") emit("close");
}

onMounted(async () => {
  previouslyFocused = document.activeElement;
  document.addEventListener("keydown", onKeydown);

  try {
    const { data } = await api.get(`/files/${props.file.id}`);
    details.value = data.details;
    versions.value = data.versions ?? [];
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
    await nextTick();
    closeButton.value?.focus();
  }
});

onBeforeUnmount(() => {
  document.removeEventListener("keydown", onKeydown);
  previouslyFocused?.focus?.();
});
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-gray-900/50 p-4"
    @click.self="emit('close')"
  >
    <div
      ref="panel"
      role="dialog"
      aria-modal="true"
      aria-labelledby="details-title"
      class="flex max-h-[90vh] w-full max-w-lg flex-col rounded-xl bg-white shadow-2xl"
    >
      <header class="flex items-start justify-between gap-4 border-b border-gray-200 p-6">
        <div class="flex min-w-0 items-center gap-3">
          <img
            v-if="file.image?.thumbnail_url"
            :src="file.image.thumbnail_url"
            :alt="file.name"
            class="h-12 w-12 shrink-0 rounded object-cover"
          />
          <i
            v-else
            :class="['fas', fileIcon(file).icon, fileIcon(file).className, 'text-2xl']"
            aria-hidden="true"
          ></i>

          <div class="min-w-0">
            <h2
              id="details-title"
              class="break-words text-h4 font-semibold text-gray-800 [overflow-wrap:anywhere]"
            >
              {{ file.name }}
            </h2>
            <p class="text-caption text-gray-500">File details</p>
          </div>
        </div>

        <button
          ref="closeButton"
          type="button"
          class="rounded-md p-2 text-gray-400 transition hover:bg-gray-100 hover:text-gray-600"
          aria-label="Close details"
          @click="emit('close')"
        >
          <i class="fas fa-xmark" aria-hidden="true"></i>
        </button>
      </header>

      <div class="min-h-0 flex-1 overflow-y-auto p-6">
        <p v-if="loading" class="text-body text-gray-500">
          <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Loading details…
        </p>

        <p
          v-else-if="error"
          role="alert"
          class="rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
        >
          {{ error }}
        </p>

        <template v-else>
          <!-- Dates -->
          <section class="mb-6">
            <h3 class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500">Dates</h3>
            <dl class="divide-y divide-gray-100">
              <div v-for="row in dateRows" :key="row.label" class="flex gap-4 py-2">
                <dt class="w-40 shrink-0 text-body-sm text-gray-500">
                  {{ row.label }}
                  <span v-if="row.hint" class="block text-caption text-gray-400">{{ row.hint }}</span>
                </dt>
                <dd class="text-body-sm text-gray-800">{{ row.value }}</dd>
              </div>
            </dl>
          </section>

          <!-- Location -->
          <section v-if="location" class="mb-6">
            <h3 class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500">
              Location
            </h3>
            <div class="rounded-base border border-gray-200 p-4">
              <p class="font-mono text-body-sm text-gray-800">
                {{ location.latitude.toFixed(6) }}, {{ location.longitude.toFixed(6) }}
              </p>
              <a
                :href="mapUrl"
                target="_blank"
                rel="noopener noreferrer"
                class="mt-2 inline-flex items-center gap-2 text-body-sm font-medium text-primary-600 hover:underline"
              >
                <i class="fas fa-map-location-dot" aria-hidden="true"></i>
                View on a map
              </a>
              <p class="mt-2 text-caption text-gray-500">
                These coordinates are stored inside the photo itself, so they travel with it if you
                share the file.
              </p>
            </div>
          </section>

          <!-- File -->
          <section class="mb-6">
            <h3 class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500">File</h3>
            <dl class="divide-y divide-gray-100">
              <div v-for="row in fileRows" :key="row.label" class="flex gap-4 py-2">
                <dt class="w-40 shrink-0 text-body-sm text-gray-500">{{ row.label }}</dt>
                <dd
                  :class="[
                    'min-w-0 break-words text-body-sm text-gray-800 [overflow-wrap:anywhere]',
                    row.mono ? 'font-mono text-caption' : '',
                  ]"
                >
                  {{ row.value }}
                </dd>
              </div>
            </dl>
          </section>

          <!-- Labels -->
          <section v-if="details.labels.length" class="mb-6">
            <h3 class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500">Labels</h3>
            <ul class="flex flex-wrap gap-2">
              <li
                v-for="label in details.labels"
                :key="label.id"
                class="rounded-full px-3 py-1 text-body-sm"
                :style="{ backgroundColor: `${label.color}1A`, color: label.color }"
              >
                {{ label.name }}
              </li>
            </ul>
          </section>

          <!-- Version history -->
          <section v-if="versions.length">
            <h3 class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500">
              Earlier versions
            </h3>
            <ul class="divide-y divide-gray-100">
              <li v-for="version in versions" :key="version.id" class="flex justify-between py-2">
                <span class="text-body-sm text-gray-700">Version {{ version.version_number }}</span>
                <span class="text-body-sm text-gray-500">
                  {{ formatFileSize(version.size) }} · {{ fullDate(version.created_at) }}
                </span>
              </li>
            </ul>
          </section>
        </template>
      </div>
    </div>
  </div>
</template>
