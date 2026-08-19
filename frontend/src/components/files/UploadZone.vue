<script setup>
import { ref } from "vue";
import { formatFileSize } from "@/utils/formatting";
import { useFilesStore } from "@/stores/files";

const props = defineProps({
  visibility: { type: String, default: "private" },
  folderId: { type: [Number, String], default: null },
});

const emit = defineEmits(["uploaded"]);
const filesStore = useFilesStore();
const fileInput = ref(null);
const isDragging = ref(false);
// dragenter/dragleave fire for every child element; counting keeps the
// highlight from flickering as the pointer moves across the zone.
const dragDepth = ref(0);

function openPicker() {
  fileInput.value?.click();
}

async function uploadAll(fileList) {
  for (const file of Array.from(fileList)) {
    try {
      const uploaded = await filesStore.upload(file, {
        visibility: props.visibility,
        folderId: props.folderId,
      });
      emit("uploaded", uploaded);
    } catch {
      // The per-file tracker carries the message; keep going with the rest.
    }
  }
}

function onSelect(event) {
  uploadAll(event.target.files);
  // Reset so picking the same file twice still fires a change event.
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
      </p>
      <p class="mt-1 text-caption text-gray-500">
        {{ visibility === "family" ? "Everyone in your family will see these" : "Only you will see these" }}
      </p>

      <input
        ref="fileInput"
        type="file"
        multiple
        class="sr-only"
        aria-label="Choose files to upload"
        @change="onSelect"
      />
    </div>

    <!-- Progress list. aria-live so screen readers hear uploads complete. -->
    <ul v-if="filesStore.uploads.length" class="mt-4 space-y-2" aria-live="polite">
      <li
        v-for="upload in filesStore.uploads"
        :key="upload.id"
        class="rounded-base border border-gray-200 bg-white p-3"
      >
        <div class="flex items-center justify-between gap-3 text-body-sm">
          <span class="truncate font-medium text-gray-700">{{ upload.name }}</span>
          <span class="shrink-0 text-caption text-gray-500">
            {{ formatFileSize(upload.size) }}
          </span>
        </div>

        <div v-if="upload.status !== 'failed'" class="mt-2 h-1 w-full overflow-hidden rounded-full bg-gray-200">
          <div
            class="h-full bg-primary-600 transition-all duration-200"
            :style="{ width: `${upload.progress}%` }"
          ></div>
        </div>

        <p v-if="upload.status === 'failed'" role="alert" class="mt-1 text-caption text-error-600">
          {{ upload.error }}
          <button type="button" class="ml-2 underline" @click="filesStore.dismissUpload(upload.id)">
            Dismiss
          </button>
        </p>
      </li>
    </ul>
  </div>
</template>
