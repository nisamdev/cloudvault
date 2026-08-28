<script setup>
import { computed, ref } from "vue";
import { formatFileSize } from "@/utils/formatting";
import { useFilesStore } from "@/stores/files";

const props = defineProps({
  visibility: { type: String, default: "private" },
  folderId: { type: [Number, String], default: null },
  // Restricts the file picker (e.g. "image/*" in the gallery). Drag and drop
  // ignores it, so the server still validates what arrives.
  accept: { type: String, default: "" },
});

const emit = defineEmits(["uploaded", "complete"]);
const filesStore = useFilesStore();
const fileInput = ref(null);
const folderInput = ref(null);
const isDragging = ref(false);
// dragenter/dragleave fire for every child element; counting keeps the
// highlight from flickering as the pointer moves across the zone.
const dragDepth = ref(0);

/** One bar for the whole picker selection — not N stacked rows. */
const batch = ref(null);

const batchPercent = computed(() => {
  if (!batch.value) return 0;
  const { totalBytes, completedBytes, currentLoaded, done, failed, total } = batch.value;
  if (totalBytes > 0) {
    return Math.min(100, Math.round(((completedBytes + currentLoaded) / totalBytes) * 100));
  }
  const finished = done + failed;
  return total ? Math.min(100, Math.round((finished / total) * 100)) : 0;
});

const batchLabel = computed(() => {
  if (!batch.value) return "";
  const { done, failed, total, currentName } = batch.value;
  const finished = done + failed;
  if (finished >= total) {
    if (failed) return `Uploaded ${done} of ${total} · ${failed} failed`;
    return total === 1 ? "Uploaded" : `Uploaded ${total} files`;
  }
  if (total === 1) return currentName || "Uploading…";
  return `Uploading ${finished + 1} of ${total}`;
});

function openPicker() {
  fileInput.value?.click();
}

function openFolderPicker() {
  folderInput.value?.click();
}

// Junk the OS drops into every folder it touches — nobody dragging a folder in
// means to upload these, and each one is just a wasted request + error card.
const JUNK_NAMES = new Set(["Thumbs.db", "desktop.ini", ".DS_Store"]);

function isAcceptableFile(file) {
  const name = file.name || "";
  return name && !name.startsWith(".") && !name.startsWith("~$") && !JUNK_NAMES.has(name);
}

async function uploadAll(fileList) {
  const queue = Array.from(fileList);
  if (!queue.length) return;

  const uploaded = [];
  let failed = 0;

  batch.value = {
    total: queue.length,
    done: 0,
    failed: 0,
    currentName: queue[0].name,
    currentLoaded: 0,
    completedBytes: 0,
    totalBytes: queue.reduce((sum, file) => sum + (file.size || 0), 0),
  };

  for (const file of queue) {
    batch.value.currentName = file.name;
    batch.value.currentLoaded = 0;

    try {
      const result = await filesStore.upload(file, {
        visibility: props.visibility,
        folderId: props.folderId,
        // Batch bar owns the UI; only keep failed rows for detail.
        track: false,
        onProgress: (_pct, event) => {
          if (!batch.value) return;
          batch.value.currentLoaded = event?.loaded ?? 0;
        },
      });
      uploaded.push(result);
      batch.value.done += 1;
      batch.value.completedBytes += file.size || 0;
      batch.value.currentLoaded = 0;
      // Per-file so the list can flash/insert as each one lands.
      emit("uploaded", result);
    } catch (e) {
      // The failure tracker (if any) carries the message; keep going.
      failed += 1;
      batch.value.failed += 1;
      batch.value.completedBytes += file.size || 0;
      batch.value.currentLoaded = 0;

      // A 429 means every request from here is going to fail the same way —
      // continuing would just fire one "too many attempts" card per remaining
      // file (and dig the rate limit hole deeper). Stop, and count the rest as
      // failed without hitting the API for each one.
      if (e?.status === 429) {
        const remaining = queue.slice(queue.indexOf(file) + 1);
        failed += remaining.length;
        batch.value.failed += remaining.length;
        batch.value.completedBytes += remaining.reduce((sum, f) => sum + (f.size || 0), 0);
        break;
      }
    }
  }

  // One summary event — callers use this for a single toast instead of N.
  emit("complete", { uploaded, failed, total: queue.length });

  // Brief "done" state, then clear so the zone stays quiet.
  setTimeout(() => {
    if (batch.value && batch.value.done + batch.value.failed >= batch.value.total) {
      batch.value = null;
    }
  }, failed ? 4000 : 1800);
}

function onSelect(event) {
  uploadAll(event.target.files);
  // Reset so picking the same file twice still fires a change event.
  event.target.value = "";
}

function onSelectFolder(event) {
  uploadAll(Array.from(event.target.files).filter(isAcceptableFile));
  event.target.value = "";
}

function onDrop(event) {
  isDragging.value = false;
  dragDepth.value = 0;
  if (event.dataTransfer?.files?.length) uploadAll(event.dataTransfer.files);
}

function onDragEnter() {
  dragDepth.value += 1;
  isDragging.value = true;
}

function onDragLeave() {
  dragDepth.value -= 1;
  if (dragDepth.value <= 0) isDragging.value = false;
}
</script>

<template>
  <div>
    <div
      :class="[
        'rounded-lg border-2 border-dashed p-8 text-center transition-colors',
        isDragging ? 'border-primary-600 bg-primary-50' : 'border-gray-300 bg-white',
      ]"
      @dragenter.prevent="onDragEnter"
      @dragover.prevent
      @dragleave.prevent="onDragLeave"
      @drop.prevent="onDrop"
    >
      <i class="fas fa-cloud-arrow-up text-3xl text-gray-400" aria-hidden="true"></i>
      <p class="mt-3 text-body text-gray-700">
        Drag files here, or
        <button
          type="button"
          class="font-semibold text-primary-600 underline hover:text-primary-700"
          @click="openPicker"
        >
          browse
        </button>
        — or
        <button
          type="button"
          class="font-semibold text-primary-600 underline hover:text-primary-700"
          @click="openFolderPicker"
        >
          upload a folder
        </button>
      </p>
      <p class="mt-1 text-caption text-gray-500">
        {{ visibility === "family" ? "Everyone in your family will see these" : "Only you will see these" }}
      </p>
      <p v-if="props.accept === 'image/*'" class="mt-1 text-caption text-gray-400">
        Images only
      </p>

      <input
        ref="fileInput"
        type="file"
        multiple
        :accept="props.accept || undefined"
        class="sr-only"
        aria-label="Choose files to upload"
        @change="onSelect"
      />
      <!-- webkitdirectory has no bearing on `accept`; the folder can hold
           anything, so unwanted types are filtered client-side and the rest
           still get server-side validation same as any other upload. -->
      <input
        ref="folderInput"
        type="file"
        multiple
        webkitdirectory
        directory
        class="sr-only"
        aria-label="Choose a folder to upload"
        @change="onSelectFolder"
      />
    </div>

    <!-- Single overall bar for the batch (and for one file). -->
    <div
      v-if="batch"
      class="mt-4 rounded-base border border-gray-200 bg-white p-3"
      aria-live="polite"
      role="status"
    >
      <div class="flex items-center justify-between gap-3 text-body-sm">
        <span class="truncate font-medium text-gray-700">{{ batchLabel }}</span>
        <span class="shrink-0 text-caption text-gray-500">{{ batchPercent }}%</span>
      </div>
      <p
        v-if="batch.total > 1 && batch.done + batch.failed < batch.total"
        class="mt-0.5 truncate text-caption text-gray-500"
      >
        {{ batch.currentName }}
      </p>
      <div class="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-gray-200">
        <div
          class="h-full bg-primary-600 transition-all duration-200"
          :style="{ width: `${batchPercent}%` }"
          role="progressbar"
          :aria-valuenow="batchPercent"
          aria-valuemin="0"
          aria-valuemax="100"
          :aria-label="batchLabel"
        ></div>
      </div>
      <p class="mt-1 text-caption text-gray-400">
        {{ formatFileSize(batch.completedBytes + batch.currentLoaded) }}
        <span v-if="batch.totalBytes"> of {{ formatFileSize(batch.totalBytes) }}</span>
      </p>
    </div>

    <!-- Failures only — so a bad file does not get lost in the batch bar. -->
    <ul
      v-if="filesStore.uploads.some((u) => u.status === 'failed')"
      class="mt-2 space-y-2"
      aria-live="polite"
    >
      <li
        v-for="upload in filesStore.uploads.filter((u) => u.status === 'failed')"
        :key="upload.id"
        class="rounded-base border border-error-200 bg-white p-3"
      >
        <div class="flex items-center justify-between gap-3 text-body-sm">
          <span class="truncate font-medium text-gray-700">{{ upload.name }}</span>
          <span class="shrink-0 text-caption text-gray-500">
            {{ formatFileSize(upload.size) }}
          </span>
        </div>
        <p role="alert" class="mt-1 text-caption text-error-600">
          {{ upload.error }}
          <button type="button" class="ml-2 underline" @click="filesStore.dismissUpload(upload.id)">
            Dismiss
          </button>
        </p>
      </li>
    </ul>
  </div>
</template>
