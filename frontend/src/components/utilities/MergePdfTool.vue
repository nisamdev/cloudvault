<script setup>
import { computed, onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import api from "@/api/client";
import { useLibraryStore } from "@/stores/library";
import { useToast } from "@/composables/useToast";
import { formatFileSize, formatRelativeDate } from "@/utils/formatting";

const emit = defineEmits(["close"]);

const router = useRouter();
const toast = useToast();
const library = useLibraryStore();

const available = ref([]);
const loading = ref(true);
const search = ref("");
const error = ref("");
const running = ref(false);

// The order here is the order of the pages in the result, so it is the whole
// point of the screen rather than a detail of it.
const chosen = ref([]);

// Where it lands, decided before running rather than discovered afterwards.
const destination = ref("");
// Kept on screen after the merge: closing the tool the moment it finished left
// people holding a filename and no idea where it had gone.
const result = ref(null);

const destinationName = computed(() => {
  if (!destination.value) return "Top level";
  return library.folders.find((f) => String(f.id) === String(destination.value))?.name ?? "Top level";
});

const matches = computed(() => {
  const term = search.value.trim().toLowerCase();
  const picked = new Set(chosen.value.map((f) => f.id));

  return available.value
    .filter((f) => !picked.has(f.id))
    .filter((f) => !term || f.name.toLowerCase().includes(term));
});

const totalSize = computed(() => chosen.value.reduce((sum, f) => sum + (f.size ?? 0), 0));

onMounted(async () => {
  try {
    const [files] = await Promise.all([
      api.get("/files", { params: { file_type: "file", per_page: 200, sort: "newest" } }),
      library.folders.length ? Promise.resolve() : library.fetchFolders(),
    ]);
    available.value = files.data.files.filter((f) => f.mime_type === "application/pdf");
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
});

function add(file) {
  chosen.value.push(file);
}

function remove(index) {
  chosen.value.splice(index, 1);
}

function move(index, by) {
  const target = index + by;
  if (target < 0 || target >= chosen.value.length) return;

  const [item] = chosen.value.splice(index, 1);
  chosen.value.splice(target, 0, item);
}

async function run() {
  running.value = true;
  error.value = "";

  try {
    const { data } = await api.post("/utilities/merge", {
      file_ids: chosen.value.map((f) => f.id),
      folder_id: destination.value || undefined,
    });

    result.value = data.file;
    chosen.value = [];

    // The new file is a PDF, so it can be merged again straight away.
    available.value = [data.file, ...available.value];

    toast.show({
      message: `Saved to ${data.file.folder?.name ?? "Top level"}`,
      detail: `${data.file.name} · ${formatFileSize(data.file.size)}`,
      actionLabel: "Show me",
      action: openResult,
    });
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    running.value = false;
  }
}

// Lands on the file itself: the right folder, with the row flashed.
function openResult() {
  router.push({
    name: "dashboard",
    query: { show: result.value.id, folder: result.value.folder?.id ?? "" },
  });
}
</script>

<template>
  <div>
    <button
      type="button"
      class="mb-4 text-body-sm font-medium text-gray-500 transition hover:text-gray-700"
      @click="emit('close')"
    >
      <i class="fas fa-arrow-left mr-1" aria-hidden="true"></i>All tools
    </button>

    <div class="rounded-lg border border-gray-200 bg-white p-6">
      <h2 class="text-h3 font-semibold text-gray-800">Merge PDFs</h2>
      <p class="mt-1 text-body-sm text-gray-500">
        Pick the documents, put them in the order you want, and they become one file.
      </p>

      <p v-if="error" role="alert" class="mt-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
        {{ error }}
      </p>

      <!-- Stays on screen. The toast is a nicety; this is the record of what
           was made and where it went. -->
      <div v-if="result" class="mt-4 rounded-base border border-success-500 bg-success-50 p-4">
        <p class="text-body-sm font-semibold text-success-700">
          <i class="fas fa-check mr-1" aria-hidden="true"></i>Merged
        </p>
        <p class="mt-1 text-body font-medium text-gray-800">{{ result.name }}</p>
        <p class="mt-0.5 text-caption text-gray-600">
          {{ formatFileSize(result.size) }} · saved in
          <strong>{{ result.folder?.name ?? "Top level" }}</strong> · only you can see it
        </p>

        <div class="mt-3 flex flex-wrap gap-2">
          <button
            type="button"
            class="rounded-base bg-success-700 px-4 py-2 text-body-sm font-semibold text-white transition hover:opacity-90"
            @click="openResult"
          >
            Open it in My Files
          </button>
          <button
            type="button"
            class="rounded-base border border-gray-300 bg-white px-4 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
            @click="result = null"
          >
            Merge more
          </button>
        </div>
      </div>

      <div class="mt-6 grid gap-6 lg:grid-cols-2">
        <!-- What is available -->
        <div>
          <h3 class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500">
            Your PDFs
          </h3>

          <label for="merge-search" class="sr-only">Search your PDFs</label>
          <input
            id="merge-search"
            v-model="search"
            type="search"
            placeholder="Search by name"
            class="mb-3 w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          />

          <div v-if="loading" class="space-y-2">
            <div v-for="n in 4" :key="n" class="h-12 animate-pulse rounded-base bg-gray-100"></div>
          </div>

          <p v-else-if="!matches.length" class="rounded-base bg-gray-50 px-4 py-6 text-center text-body-sm text-gray-500">
            <template v-if="available.length">Nothing else matches.</template>
            <template v-else>You have no PDFs yet.</template>
          </p>

          <ul v-else class="max-h-96 space-y-2 overflow-y-auto pr-1">
            <li v-for="file in matches" :key="file.id">
              <button
                type="button"
                class="flex w-full items-center gap-3 rounded-base border border-gray-200 p-3 text-left transition hover:border-primary-300 hover:bg-primary-50"
                @click="add(file)"
              >
                <i class="fas fa-file-pdf text-error-500" aria-hidden="true"></i>
                <span class="min-w-0 flex-1">
                  <span class="block truncate text-body-sm font-medium text-gray-800">{{ file.name }}</span>
                  <span class="block text-caption text-gray-500">
                    {{ formatFileSize(file.size) }} · {{ formatRelativeDate(file.created_at) }}
                  </span>
                </span>
                <i class="fas fa-plus text-gray-400" aria-hidden="true"></i>
              </button>
            </li>
          </ul>
        </div>

        <!-- The order they will end up in -->
        <div>
          <h3 class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500">
            In this order
          </h3>

          <p
            v-if="!chosen.length"
            class="rounded-base border-2 border-dashed border-gray-300 px-4 py-10 text-center text-body-sm text-gray-500"
          >
            Pick two or more from the left. The first one you pick comes first.
          </p>

          <ol v-else class="space-y-2">
            <li
              v-for="(file, index) in chosen"
              :key="file.id"
              class="flex items-center gap-3 rounded-base border border-gray-200 bg-gray-50 p-3"
            >
              <span class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary-600 text-caption font-semibold text-white">
                {{ index + 1 }}
              </span>

              <span class="min-w-0 flex-1 truncate text-body-sm font-medium text-gray-800">
                {{ file.name }}
              </span>

              <span class="flex shrink-0 items-center gap-0.5">
                <button
                  type="button"
                  :disabled="index === 0"
                  class="rounded-md p-1.5 text-gray-500 transition hover:bg-gray-200 disabled:opacity-30"
                  :aria-label="`Move ${file.name} earlier`"
                  @click="move(index, -1)"
                >
                  <i class="fas fa-arrow-up" aria-hidden="true"></i>
                </button>
                <button
                  type="button"
                  :disabled="index === chosen.length - 1"
                  class="rounded-md p-1.5 text-gray-500 transition hover:bg-gray-200 disabled:opacity-30"
                  :aria-label="`Move ${file.name} later`"
                  @click="move(index, 1)"
                >
                  <i class="fas fa-arrow-down" aria-hidden="true"></i>
                </button>
                <button
                  type="button"
                  class="rounded-md p-1.5 text-error-500 transition hover:bg-error-50"
                  :aria-label="`Remove ${file.name}`"
                  @click="remove(index)"
                >
                  <i class="fas fa-xmark" aria-hidden="true"></i>
                </button>
              </span>
            </li>
          </ol>

          <div v-if="chosen.length" class="mt-4">
            <label for="merge-destination" class="mb-1 block text-body-sm font-medium text-gray-700">
              Save it in
            </label>
            <select
              id="merge-destination"
              v-model="destination"
              class="mb-3 w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
            >
              <option value="">Top level</option>
              <option v-for="folder in library.folders" :key="folder.id" :value="folder.id">
                {{ folder.name }}
              </option>
            </select>

            <p class="mb-3 text-caption text-gray-500">
              {{ chosen.length }} documents · {{ formatFileSize(totalSize) }} into
              <strong>{{ destinationName }}</strong>, as a new private file. The originals are
              untouched.
            </p>

            <button
              type="button"
              :disabled="running || chosen.length < 2"
              class="w-full rounded-base gradient-main py-2 font-semibold text-white disabled:opacity-60"
              @click="run"
            >
              <span v-if="running">
                <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Merging…
              </span>
              <span v-else>Merge {{ chosen.length }} documents</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
