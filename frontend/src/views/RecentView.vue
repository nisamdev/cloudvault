<script setup>
import { computed, onMounted, ref } from "vue";
import { useFilesStore } from "@/stores/files";
import { useContextMenu } from "@/composables/useContextMenu";
import FilePreview from "@/components/files/FilePreview.vue";
import FileDetails from "@/components/files/FileDetails.vue";
import ShareModal from "@/components/files/ShareModal.vue";
import ContextMenu from "@/components/ui/ContextMenu.vue";
import { formatFileSize, fileIcon, groupByDate } from "@/utils/formatting";

const filesStore = useFilesStore();
const contextMenu = useContextMenu();

const previewFile = ref(null);
const detailsFile = ref(null);
const sharingFile = ref(null);
const refreshing = ref(false);

// Everything the user can see, newest first, across every folder — the point of
// this screen is "what did I just put in here".
const groups = computed(() => groupByDate(filesStore.items, "created_at"));

onMounted(load);

function load() {
  return filesStore.fetchFiles({ filters: { sort: "newest" }, page: 1 });
}

async function refresh() {
  refreshing.value = true;
  try {
    await load();
  } finally {
    refreshing.value = false;
  }
}

async function onDownload(file) {
  try {
    await filesStore.download(file);
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

function menu(event, file) {
  contextMenu.open(event, {
    title: file.name,
    items: [
      { label: "Preview", icon: "fa-eye", action: () => (previewFile.value = file) },
      { label: "Download", icon: "fa-download", action: () => onDownload(file) },
      { label: "Details", icon: "fa-circle-info", action: () => (detailsFile.value = file) },
      file.permissions.can_share && {
        label: "Share…", icon: "fa-share-nodes", action: () => (sharingFile.value = file),
      },
    ],
  });
}
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-center justify-between gap-4">
      <div>
        <h1 class="text-h2 font-bold text-gray-800">Recent</h1>
        <p class="mt-1 text-body-sm text-gray-500">
          Everything you've added lately, newest first
        </p>
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
    </header>

    <p
      v-if="filesStore.error"
      role="alert"
      class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
    >
      {{ filesStore.error }}
    </p>

    <div v-if="filesStore.loading" class="space-y-2">
      <div v-for="n in 5" :key="n" class="h-16 animate-pulse rounded-lg bg-gray-100"></div>
    </div>

    <div v-else-if="filesStore.isEmpty" class="rounded-lg border border-gray-200 bg-white p-12 text-center">
      <i class="fas fa-clock-rotate-left text-4xl text-gray-300" aria-hidden="true"></i>
      <h2 class="mt-4 text-h3 font-semibold text-gray-800">Nothing here yet</h2>
      <p class="mt-2 text-body text-gray-500">Files you add will show up here.</p>
    </div>

    <template v-else>
      <section v-for="group in groups" :key="group.label" class="mb-6">
        <h2 class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500">
          {{ group.label }}
        </h2>

        <ul class="space-y-2">
          <li
            v-for="file in group.items"
            :key="file.id"
            class="flex items-center gap-4 rounded-lg border border-gray-200 bg-white p-4 transition hover:shadow-md"
            @contextmenu="menu($event, file)"
          >
            <img
              v-if="file.image?.thumbnail_url"
              :src="file.image.thumbnail_url"
              :alt="file.name"
              class="h-10 w-10 shrink-0 rounded object-cover"
              loading="lazy"
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
                {{ formatFileSize(file.size) }}
                <span v-if="file.folder"> · {{ file.folder.name }}</span>
                · {{ file.owner.name }}
              </p>
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
                type="button"
                class="rounded-md p-2 text-gray-500 transition hover:bg-gray-100 hover:text-gray-700"
                :aria-label="`Download ${file.name}`"
                @click="onDownload(file)"
              >
                <i class="fas fa-download" aria-hidden="true"></i>
              </button>
            </div>
          </li>
        </ul>
      </section>
    </template>

    <ContextMenu />
    <FilePreview
      v-if="previewFile"
      :file="previewFile"
      :files="filesStore.items"
      @navigate="previewFile = $event"
      @close="previewFile = null"
    />
    <FileDetails v-if="detailsFile" :file="detailsFile" @close="detailsFile = null" />
    <ShareModal v-if="sharingFile" kind="file" :subject="sharingFile" @close="sharingFile = null" />
  </section>
</template>
