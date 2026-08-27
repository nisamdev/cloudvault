<script setup>
import { computed, onMounted, ref, watch } from "vue";
import api from "@/api/client";
import { useFilesStore } from "@/stores/files";
import { formatFileSize, fileIcon } from "@/utils/formatting";

/**
 * Link files from My Files to a record, or upload new ones inline.
 */
const props = defineProps({
  modelValue: { type: Array, default: () => [] },
  /** Matches record visibility — private uploads stay private, family ones are shared. */
  visibility: { type: String, default: "private" },
});

const emit = defineEmits(["update:modelValue"]);

const filesStore = useFilesStore();
const files = ref([]);
const loading = ref(true);
const error = ref("");
const search = ref("");
const open = ref(false);
const fileInput = ref(null);
const uploading = ref(false);
const uploadLabel = ref("");

const selected = computed({
  get: () => new Set(props.modelValue),
  set: (ids) => emit("update:modelValue", [...ids]),
});

const selectedFiles = computed(() =>
  props.modelValue.map((id) => files.value.find((f) => f.id === id)).filter(Boolean),
);

const matches = computed(() => {
  const term = search.value.trim().toLowerCase();
  if (!term) return files.value;
  return files.value.filter((f) => f.name.toLowerCase().includes(term));
});

onMounted(loadFiles);

watch(
  () => props.modelValue.length,
  (n) => {
    if (n) open.value = true;
  },
  { immediate: true },
);

async function loadFiles() {
  loading.value = true;
  error.value = "";
  try {
    const { data } = await api.get("/files", { params: { per_page: 200, sort: "newest" } });
    files.value = data.files;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}

function toggle(id) {
  const next = new Set(selected.value);
  next.has(id) ? next.delete(id) : next.add(id);
  selected.value = next;
}

function remove(id) {
  const next = new Set(selected.value);
  next.delete(id);
  selected.value = next;
}

function openUpload() {
  fileInput.value?.click();
}

function addUploaded(file) {
  const existing = files.value.findIndex((f) => f.id === file.id);
  if (existing >= 0) {
    files.value.splice(existing, 1, file);
  } else {
    files.value.unshift(file);
  }

  const next = new Set(selected.value);
  next.add(file.id);
  selected.value = next;
  open.value = true;
}

async function onUploadSelect(event) {
  const queue = Array.from(event.target.files ?? []);
  event.target.value = "";
  if (!queue.length) return;

  uploading.value = true;
  error.value = "";

  for (let i = 0; i < queue.length; i += 1) {
    const file = queue[i];
    uploadLabel.value = queue.length === 1 ? file.name : `${file.name} (${i + 1} of ${queue.length})`;
    try {
      const uploaded = await filesStore.upload(file, {
        visibility: props.visibility,
        track: false,
      });
      addUploaded(uploaded);
    } catch (e) {
      error.value = e.userMessage || "Upload failed.";
    }
  }

  uploading.value = false;
  uploadLabel.value = "";
}
</script>

<template>
  <div>
    <!-- Linked files -->
    <ul v-if="selectedFiles.length" class="mb-3 space-y-1">
      <li
        v-for="file in selectedFiles"
        :key="file.id"
        class="flex items-center gap-2 text-body-sm text-gray-800"
      >
        <i :class="['fas text-gray-400', fileIcon(file)]" aria-hidden="true"></i>
        <span class="min-w-0 flex-1 truncate">{{ file.name }}</span>
        <button
          type="button"
          class="text-gray-400 hover:text-error-600"
          :aria-label="`Remove ${file.name}`"
          @click="remove(file.id)"
        >
          <i class="fas fa-xmark" aria-hidden="true"></i>
        </button>
      </li>
    </ul>

    <div class="flex flex-wrap items-center gap-x-4 gap-y-1">
      <button
        type="button"
        class="text-body-sm font-medium text-primary-600 hover:text-primary-700"
        @click="open = !open"
      >
        <i :class="['fas mr-1', open ? 'fa-chevron-up' : 'fa-plus']" aria-hidden="true"></i>
        {{ open ? "Hide file list" : "Link from My Files" }}
      </button>

      <button
        type="button"
        class="text-body-sm font-medium text-primary-600 hover:text-primary-700 disabled:opacity-60"
        :disabled="uploading"
        @click="openUpload"
      >
        <i class="fas fa-arrow-up-from-bracket mr-1" aria-hidden="true"></i>
        {{ uploading ? "Uploading…" : "Upload" }}
      </button>

      <input
        ref="fileInput"
        type="file"
        multiple
        class="sr-only"
        aria-label="Upload files to My Files"
        @change="onUploadSelect"
      />
    </div>

    <p v-if="uploading && uploadLabel" class="mt-2 truncate text-caption text-gray-500" aria-live="polite">
      {{ uploadLabel }}
    </p>

    <div v-if="open" class="mt-3 space-y-2">
      <input
        v-model="search"
        type="search"
        placeholder="Search files…"
        aria-label="Search My Files"
        class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
      />

      <p v-if="error" role="alert" class="text-caption text-error-600">{{ error }}</p>

      <div v-if="loading" class="py-4 text-body-sm text-gray-400">Loading…</div>

      <p v-else-if="!files.length" class="text-body-sm text-gray-500">
        No files yet — upload above or add them in My Files.
      </p>

      <ul v-else class="max-h-48 space-y-0.5 overflow-y-auto rounded-base border border-gray-200">
        <li v-for="file in matches" :key="file.id">
          <button
            type="button"
            :aria-pressed="selected.has(file.id)"
            class="flex w-full items-center gap-2 px-3 py-2 text-left text-body-sm hover:bg-gray-50"
            @click="toggle(file.id)"
          >
            <i
              :class="['fas w-4', selected.has(file.id) ? 'fa-check text-primary-600' : 'fa-plus text-gray-300']"
              aria-hidden="true"
            ></i>
            <i :class="['fas text-gray-400', fileIcon(file)]" aria-hidden="true"></i>
            <span class="min-w-0 flex-1 truncate">{{ file.name }}</span>
            <span class="text-caption text-gray-400">{{ formatFileSize(file.size) }}</span>
          </button>
        </li>
      </ul>
    </div>
  </div>
</template>
