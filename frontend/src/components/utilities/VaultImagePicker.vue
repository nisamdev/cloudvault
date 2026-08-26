<script setup>
import { computed, onMounted, ref } from "vue";
import api from "@/api/client";
import { formatFileSize, formatRelativeDate } from "@/utils/formatting";

/**
 * Picks photos that are already in the vault, so the scanner is not limited to
 * whatever is on the device in front of you.
 *
 * The bytes come back through the API rather than straight from storage. A
 * presigned storage URL is a different origin, and a canvas that has drawn a
 * cross-origin image cannot be read back — which is the entire job here.
 */
const emit = defineEmits(["close", "add"]);

const files = ref([]);
const loading = ref(true);
const fetching = ref(false);
const error = ref("");
const search = ref("");
const chosen = ref(new Set());

const matches = computed(() => {
  const term = search.value.trim().toLowerCase();
  return term ? files.value.filter((f) => f.name.toLowerCase().includes(term)) : files.value;
});

onMounted(async () => {
  try {
    const { data } = await api.get("/files", {
      params: { file_type: "image", per_page: 100, sort: "newest" },
    });
    files.value = data.files;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
});

function toggle(file) {
  const next = new Set(chosen.value);
  next.has(file.id) ? next.delete(file.id) : next.add(file.id);
  chosen.value = next;
}

async function confirm() {
  const picked = files.value.filter((file) => chosen.value.has(file.id));
  if (!picked.length) return;

  fetching.value = true;
  error.value = "";

  try {
    const blobs = [];
    for (const file of picked) {
      // via=proxy: same-origin bytes, so the editor can read the pixels.
      const { data } = await api.get(`/files/${file.id}/preview`, { params: { via: "proxy" } });
      if (!data.url) throw new Error(`${file.name} has no contents.`);

      const response = await fetch(data.url, { credentials: "same-origin" });
      if (!response.ok) throw new Error(`${file.name} could not be loaded.`);

      blobs.push({ blob: await response.blob(), name: file.name });
    }

    emit("add", blobs);
    emit("close");
  } catch (e) {
    error.value = e.userMessage ?? e.message;
  } finally {
    fetching.value = false;
  }
}
</script>

<template>
  <div
    class="fixed inset-0 z-40 flex items-center justify-center bg-gray-900/50 p-4"
    @click.self="emit('close')"
  >
    <div
      class="flex max-h-[85vh] w-full max-w-3xl flex-col rounded-xl bg-white shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-labelledby="vault-picker-title"
    >
      <header class="flex items-start justify-between border-b border-gray-200 p-6">
        <div>
          <h2 id="vault-picker-title" class="text-h3 font-semibold text-gray-800">
            Add from your photos
          </h2>
          <p class="mt-1 text-body-sm text-gray-500">
            Pick as many as you like. They stay where they are — a copy comes into the scanner.
          </p>
        </div>
        <button
          type="button"
          class="rounded-md p-2 text-gray-400 transition hover:bg-gray-100 hover:text-gray-600"
          aria-label="Close"
          @click="emit('close')"
        >
          <i class="fas fa-xmark" aria-hidden="true"></i>
        </button>
      </header>

      <div class="border-b border-gray-100 px-6 py-3">
        <label for="vault-picker-search" class="sr-only">Search your photos</label>
        <input
          id="vault-picker-search"
          v-model="search"
          type="search"
          placeholder="Search by name"
          class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
        />
      </div>

      <div class="min-h-0 flex-1 overflow-y-auto p-6">
        <p v-if="error" role="alert" class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
          {{ error }}
        </p>

        <div v-if="loading" class="grid grid-cols-3 gap-3 sm:grid-cols-4">
          <div v-for="n in 8" :key="n" class="aspect-square animate-pulse rounded-base bg-gray-100"></div>
        </div>

        <p v-else-if="!matches.length" class="py-10 text-center text-body-sm text-gray-500">
          <template v-if="files.length">Nothing matches that.</template>
          <template v-else>You have no photos in CloudVault yet.</template>
        </p>

        <ul v-else class="grid grid-cols-3 gap-3 sm:grid-cols-4">
          <li v-for="file in matches" :key="file.id">
            <button
              type="button"
              :aria-pressed="chosen.has(file.id)"
              :class="[
                'group relative block w-full overflow-hidden rounded-base border-2 transition',
                chosen.has(file.id) ? 'border-primary-600' : 'border-transparent hover:border-gray-300',
              ]"
              @click="toggle(file)"
            >
              <img
                v-if="file.image?.thumbnail_url"
                :src="file.image.thumbnail_url"
                :alt="file.name"
                class="aspect-square w-full bg-gray-100 object-cover"
                loading="lazy"
              />
              <span v-else class="flex aspect-square w-full items-center justify-center bg-gray-100">
                <i class="fas fa-file-image text-2xl text-gray-300" aria-hidden="true"></i>
              </span>

              <span
                v-if="chosen.has(file.id)"
                class="absolute right-1.5 top-1.5 flex h-6 w-6 items-center justify-center rounded-full bg-primary-600 text-caption text-white"
              >
                <i class="fas fa-check" aria-hidden="true"></i>
              </span>

              <span class="block truncate px-1 py-1 text-left text-caption text-gray-600">
                {{ file.name }}
              </span>
              <span class="block truncate px-1 pb-1 text-left text-caption text-gray-400">
                {{ formatFileSize(file.size) }} · {{ formatRelativeDate(file.created_at) }}
              </span>
            </button>
          </li>
        </ul>
      </div>

      <footer class="flex items-center justify-between gap-3 border-t border-gray-200 p-4">
        <p class="text-body-sm text-gray-500">
          {{ chosen.size }} selected
        </p>
        <div class="flex gap-2">
          <button
            type="button"
            class="rounded-base border border-gray-300 px-4 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
            @click="emit('close')"
          >
            Cancel
          </button>
          <button
            type="button"
            :disabled="!chosen.size || fetching"
            class="rounded-base gradient-main px-4 py-2 text-body-sm font-semibold text-white disabled:opacity-60"
            @click="confirm"
          >
            <span v-if="fetching">
              <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Fetching…
            </span>
            <span v-else>Add {{ chosen.size || "" }}</span>
          </button>
        </div>
      </footer>
    </div>
  </div>
</template>
