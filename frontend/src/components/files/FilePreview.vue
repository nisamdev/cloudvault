<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import api from "@/api/client";
import { useFilesStore } from "@/stores/files";
import { formatFileSize, fileIcon } from "@/utils/formatting";

const props = defineProps({
  file: { type: Object, required: true },
  // The surrounding list, so the arrows can step through it like a gallery.
  files: { type: Array, default: () => [] },
});
const emit = defineEmits(["close", "navigate"]);

const filesStore = useFilesStore();

const preview = ref(null);
const loading = ref(true);
const error = ref("");
const closeButton = ref(null);
let previouslyFocused = null;

const index = computed(() => props.files.findIndex((f) => f.id === props.file.id));
const hasPrev = computed(() => index.value > 0);
const hasNext = computed(() => index.value >= 0 && index.value < props.files.length - 1);

async function load() {
  loading.value = true;
  error.value = "";
  preview.value = null;

  try {
    const { data } = await api.get(`/files/${props.file.id}/preview`);
    preview.value = data;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}

// Re-fetch when the arrows move to another file.
watch(() => props.file.id, load);

function go(step) {
  const next = props.files[index.value + step];
  if (next) emit("navigate", next);
}

function onKeydown(event) {
  switch (event.key) {
    case "Escape":
      emit("close");
      break;
    case "ArrowLeft":
      if (hasPrev.value) go(-1);
      break;
    case "ArrowRight":
      if (hasNext.value) go(1);
      break;
    default:
      break;
  }
}

async function download() {
  try {
    await filesStore.download(props.file);
  } catch (e) {
    error.value = e.userMessage;
  }
}

onMounted(async () => {
  previouslyFocused = document.activeElement;
  document.addEventListener("keydown", onKeydown);
  // The page behind must not scroll while the overlay is up.
  document.body.style.overflow = "hidden";
  await load();
  closeButton.value?.focus();
});

onBeforeUnmount(() => {
  document.removeEventListener("keydown", onKeydown);
  document.body.style.overflow = "";
  previouslyFocused?.focus?.();
});
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex flex-col bg-gray-900/90"
    role="dialog"
    aria-modal="true"
    aria-labelledby="preview-title"
    @click.self="emit('close')"
  >
    <!-- Toolbar -->
    <header class="flex shrink-0 items-center gap-4 px-4 py-3 text-white">
      <i :class="['fas', fileIcon(file).icon, 'text-lg']" aria-hidden="true"></i>

      <div class="min-w-0 flex-1">
        <h2 id="preview-title" class="truncate text-body font-medium">{{ file.name }}</h2>
        <p class="text-caption text-gray-300">
          {{ formatFileSize(file.size) }}
          <span v-if="file.image?.taken_at">
            · taken {{ new Date(file.image.taken_at).toLocaleString() }}
          </span>
          <span v-if="file.image?.camera"> · {{ file.image.camera }}</span>
          <span v-if="preview?.truncated"> · showing the first 512 KB</span>
        </p>
      </div>

      <a
        v-if="file.image?.location"
        :href="`https://www.openstreetmap.org/?mlat=${file.image.location.latitude}&mlon=${file.image.location.longitude}#map=15/${file.image.location.latitude}/${file.image.location.longitude}`"
        target="_blank"
        rel="noopener noreferrer"
        class="rounded-md px-3 py-2 text-body-sm font-medium transition hover:bg-white/10"
        :title="`${file.image.location.latitude}, ${file.image.location.longitude}`"
      >
        <i class="fas fa-location-dot mr-2" aria-hidden="true"></i>Where
      </a>

      <button
        type="button"
        class="rounded-md px-3 py-2 text-body-sm font-medium transition hover:bg-white/10"
        @click="download"
      >
        <i class="fas fa-download mr-2" aria-hidden="true"></i>Download
      </button>

      <button
        ref="closeButton"
        type="button"
        class="rounded-md p-2 transition hover:bg-white/10"
        aria-label="Close preview"
        @click="emit('close')"
      >
        <i class="fas fa-xmark text-lg" aria-hidden="true"></i>
      </button>
    </header>

    <!-- Body -->
    <div class="relative flex min-h-0 flex-1 items-center justify-center p-4" @click.self="emit('close')">
      <button
        v-if="hasPrev"
        type="button"
        class="absolute left-4 z-10 rounded-full bg-white/10 p-3 text-white transition hover:bg-white/20"
        aria-label="Previous file"
        @click="go(-1)"
      >
        <i class="fas fa-chevron-left" aria-hidden="true"></i>
      </button>

      <button
        v-if="hasNext"
        type="button"
        class="absolute right-4 z-10 rounded-full bg-white/10 p-3 text-white transition hover:bg-white/20"
        aria-label="Next file"
        @click="go(1)"
      >
        <i class="fas fa-chevron-right" aria-hidden="true"></i>
      </button>

      <p v-if="loading" class="text-body text-gray-300">
        <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Loading preview…
      </p>

      <p
        v-else-if="error"
        role="alert"
        class="rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
      >
        {{ error }}
      </p>

      <img
        v-else-if="preview.kind === 'image'"
        :src="preview.url"
        :alt="file.name"
        class="max-h-full max-w-full rounded-lg object-contain shadow-2xl"
      />

      <!--
        <object> rather than <iframe>: Chrome refuses to run its PDF viewer
        inside a sandboxed frame ("This page has been blocked by Chrome"), and
        an unsandboxed iframe gives no fallback when the browser has no viewer
        at all. <object> renders its children in that case.

        No sandbox is needed: the PDF is served from object storage on a
        different origin, so it has no access to this one either way.
      -->
      <div v-else-if="preview.kind === 'pdf'" class="flex h-full w-full max-w-5xl flex-col gap-2">
        <object
          :data="preview.url"
          type="application/pdf"
          :aria-label="file.name"
          class="min-h-0 flex-1 rounded-lg bg-white shadow-2xl"
        >
          <div class="flex h-full flex-col items-center justify-center rounded-lg bg-white p-12 text-center">
            <i class="fas fa-file-pdf text-5xl text-error-500" aria-hidden="true"></i>
            <h3 class="mt-4 text-h3 font-semibold text-gray-800">Your browser can't display PDFs</h3>
            <p class="mt-2 text-body text-gray-500">Open it in a new tab or download it instead.</p>
            <div class="mt-6 flex gap-3">
              <a
                :href="preview.url"
                target="_blank"
                rel="noopener noreferrer"
                class="rounded-base gradient-main px-6 py-2 font-semibold text-white"
              >
                Open in a new tab
              </a>
              <button
                type="button"
                class="rounded-base border border-gray-300 px-6 py-2 font-medium text-gray-700 hover:bg-gray-50"
                @click="download"
              >
                Download
              </button>
            </div>
          </div>
        </object>

        <p class="text-center text-caption text-gray-400">
          Not showing?
          <a :href="preview.url" target="_blank" rel="noopener noreferrer" class="underline hover:text-white">
            Open in a new tab
          </a>
        </p>
      </div>

      <video
        v-else-if="preview.kind === 'video'"
        :src="preview.url"
        controls
        class="max-h-full max-w-full rounded-lg shadow-2xl"
      ></video>

      <audio v-else-if="preview.kind === 'audio'" :src="preview.url" controls class="w-full max-w-lg"></audio>

      <pre
        v-else-if="preview.kind === 'text'"
        class="h-full w-full max-w-5xl overflow-auto rounded-lg bg-white p-6 text-body-sm leading-relaxed text-gray-800 shadow-2xl"
      ><code>{{ preview.text }}</code></pre>

      <!-- Nothing we can render in the browser -->
      <div v-else class="rounded-lg bg-white p-12 text-center shadow-2xl">
        <i :class="['fas', fileIcon(file).icon, fileIcon(file).className, 'text-5xl']" aria-hidden="true"></i>
        <h3 class="mt-4 text-h3 font-semibold text-gray-800">No preview available</h3>
        <p class="mt-2 text-body text-gray-500">
          {{ preview?.reason === "empty" ? "This file has no contents." : "This file type can't be shown in the browser." }}
        </p>
        <button
          type="button"
          class="mt-6 rounded-base gradient-main px-6 py-2 font-semibold text-white"
          @click="download"
        >
          Download instead
        </button>
      </div>
    </div>

    <footer v-if="files.length > 1" class="shrink-0 pb-3 text-center text-caption text-gray-400">
      {{ index + 1 }} of {{ files.length }} · use ← and → to move between files
    </footer>
  </div>
</template>
