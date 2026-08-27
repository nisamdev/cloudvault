<script setup>
import { computed, onMounted, ref } from "vue";
import api from "@/api/client";
import { useFilesStore } from "@/stores/files";
import { formatFileSize, fileIcon } from "@/utils/formatting";

/**
 * Choose the document to read.
 *
 * Only what OCR can actually open: a photograph or a PDF. And PDFs first, not
 * newest first — the whole vault sorted by date buries the one scanned licence
 * under a month of pictures of the garden.
 */
const emit = defineEmits(["select", "cancel"]);

const filesStore = useFilesStore();
const files = ref([]);
const loading = ref(true);
const error = ref("");
const search = ref("");
const uploading = ref(false);
const fileInput = ref(null);

const READABLE = /^(image\/|application\/pdf$)/;

const readable = computed(() => files.value.filter((f) => READABLE.test(f.mime_type ?? "")));

const matches = computed(() => {
  const term = search.value.trim().toLowerCase();
  const found = term
    ? readable.value.filter((f) => f.name.toLowerCase().includes(term))
    : readable.value;

  // A document you scanned is nearly always the one you want; a photograph is
  // nearly always noise you are scrolling past.
  return [...found].sort((a, b) => Number(isPdf(b)) - Number(isPdf(a)));
});

function isPdf(file) {
  return file.mime_type === "application/pdf";
}

onMounted(async () => {
  try {
    const { data } = await api.get("/files", { params: { per_page: 200, sort: "newest" } });
    files.value = data.files;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
});

function openUpload() {
  fileInput.value?.click();
}

async function onUploadSelect(event) {
  const [file] = Array.from(event.target.files ?? []);
  event.target.value = "";
  if (!file) return;

  uploading.value = true;
  error.value = "";
  try {
    emit("select", await filesStore.upload(file, { visibility: "private", track: false }));
  } catch (e) {
    error.value = e.userMessage || "That file couldn't be uploaded.";
  } finally {
    uploading.value = false;
  }
}
</script>

<template>
  <div class="rounded-lg border border-gray-200 bg-white p-5">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h2 class="text-body font-semibold text-gray-800">Which document?</h2>
        <p class="mt-0.5 text-body-sm text-gray-500">
          A photograph or a PDF. You can straighten it before it's read.
        </p>
      </div>

      <div class="flex items-center gap-3">
        <button
          type="button"
          class="text-body-sm font-medium text-primary-600 hover:text-primary-700 disabled:opacity-60"
          :disabled="uploading"
          @click="openUpload"
        >
          <i class="fas fa-arrow-up-from-bracket mr-1" aria-hidden="true"></i>
          {{ uploading ? "Uploading…" : "From this computer" }}
        </button>
        <button
          type="button"
          class="text-body-sm font-medium text-gray-600 hover:text-gray-800"
          @click="emit('cancel')"
        >
          Cancel
        </button>
      </div>
    </div>

    <input
      ref="fileInput"
      type="file"
      accept="image/*,application/pdf"
      class="sr-only"
      aria-label="Upload a document to read"
      @change="onUploadSelect"
    />

    <p v-if="error" role="alert" class="mt-3 text-caption text-error-600">{{ error }}</p>

    <input
      v-model="search"
      type="search"
      placeholder="Search My Files…"
      aria-label="Search My Files"
      class="mt-4 w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
    />

    <p v-if="loading" class="mt-4 text-body-sm text-gray-400">Loading…</p>

    <p v-else-if="!matches.length" class="mt-4 text-body-sm text-gray-500">
      Nothing here that can be read. Upload a photograph or a PDF above.
    </p>

    <ul v-else class="mt-3 max-h-72 space-y-0.5 overflow-y-auto rounded-base border border-gray-200">
      <li v-for="file in matches" :key="file.id">
        <button
          type="button"
          class="flex w-full items-center gap-3 px-3 py-2 text-left text-body-sm hover:bg-gray-50"
          @click="emit('select', file)"
        >
          <i :class="['fas w-4 text-gray-400', fileIcon(file)]" aria-hidden="true"></i>
          <span class="min-w-0 flex-1 truncate text-gray-800">{{ file.name }}</span>
          <span
            v-if="isPdf(file)"
            class="shrink-0 rounded-full bg-gray-100 px-2 py-0.5 text-caption text-gray-600"
          >
            PDF
          </span>
          <span class="shrink-0 text-caption text-gray-400">{{ formatFileSize(file.size) }}</span>
        </button>
      </li>
    </ul>
  </div>
</template>
