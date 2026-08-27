<script setup>
import { computed, onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import api from "@/api/client";
import { usePdfPages } from "@/composables/usePdfPages";
import { useToast } from "@/composables/useToast";
import { formatFileSize, formatRelativeDate } from "@/utils/formatting";

/**
 * Reordering, turning and dropping pages inside a PDF.
 *
 * The pages come back from the API as images, because the browser has no PDF
 * renderer and this screen only needs to show which page is which. What gets
 * sent back is the whole layout — the document as it should end up — rather
 * than the sequence of moves that got there.
 */
const emit = defineEmits(["close"]);

const router = useRouter();
const toast = useToast();
const { pages: rendered, pageCount, loading: loadingPages, load: loadPages } = usePdfPages();

const documents = ref([]);
const loading = ref(true);
const search = ref("");
const error = ref("");

const chosen = ref(null);
const pages = ref([]);
const removed = ref([]);
const saving = ref(false);
const result = ref(null);

let dragFrom = null;

const matches = computed(() => {
  const term = search.value.trim().toLowerCase();
  return documents.value.filter((f) => !term || f.name.toLowerCase().includes(term));
});

/** Save is only worth offering once the document would actually come out different. */
const changed = computed(
  () =>
    pages.value.length !== pageCount.value ||
    pages.value.some((page, index) => page.number !== index + 1 || page.rotation !== 0),
);

onMounted(async () => {
  try {
    const { data } = await api.get("/files", {
      params: { file_type: "file", per_page: 200, sort: "newest" },
    });
    documents.value = data.files.filter((f) => f.mime_type === "application/pdf");
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
});

/* ------------------------------------------------------------ the pages */

async function open(file) {
  chosen.value = file;
  pages.value = [];
  removed.value = [];
  result.value = null;
  error.value = "";

  try {
    await loadPages(file.id);
    // Rotation is this tool's own idea; the pages come back as they are.
    pages.value = rendered.value.map((page) => ({ ...page, rotation: 0 }));
  } catch (e) {
    error.value = e.userMessage;
    chosen.value = null;
  }
}

function back() {
  chosen.value = null;
  pages.value = [];
  removed.value = [];
  result.value = null;
}

function move(index, by) {
  const target = index + by;
  if (target < 0 || target >= pages.value.length) return;

  const next = [...pages.value];
  [next[index], next[target]] = [next[target], next[index]];
  pages.value = next;
}

function rotate(page, degrees) {
  page.rotation = (((page.rotation + degrees) % 360) + 360) % 360;
}

function remove(index) {
  removed.value.push(pages.value[index]);
  pages.value.splice(index, 1);
}

function restore(page) {
  removed.value = removed.value.filter((p) => p.number !== page.number);
  // Back to where it came from, as far as the pages still present allow.
  const at = pages.value.findIndex((p) => p.number > page.number);
  pages.value.splice(at < 0 ? pages.value.length : at, 0, page);
}

function reset() {
  pages.value = [...pages.value, ...removed.value]
    .sort((a, b) => a.number - b.number)
    .map((page) => ({ ...page, rotation: 0 }));
  removed.value = [];
}

/* ---------------------------------------------------------------- drag */

function onDragStart(index) {
  dragFrom = index;
}

function onDrop(index) {
  if (dragFrom === null || dragFrom === index) return;

  const next = [...pages.value];
  const [page] = next.splice(dragFrom, 1);
  next.splice(index, 0, page);
  pages.value = next;
  dragFrom = null;
}

/* --------------------------------------------------------------- saving */

async function save() {
  if (!changed.value || saving.value) return;

  saving.value = true;
  error.value = "";

  try {
    const { data } = await api.patch(
      `/files/${chosen.value.id}/pages`,
      { pages: pages.value.map((page) => ({ number: page.number, rotation: page.rotation })) },
      { timeout: 120_000 },
    );

    result.value = data.file;
    toast.show({
      message: "Pages saved",
      detail: `${data.file.name} · version ${data.file.version_number}`,
      actionLabel: "Show me",
      action: openResult,
    });
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    saving.value = false;
  }
}

function openResult() {
  router.push({
    name: "dashboard",
    query: { show: result.value.id, folder: result.value.folder?.id ?? "" },
  });
}

/** Reopens the file it just wrote, so a second pass starts from the new pages. */
function editAgain() {
  const file = result.value;
  result.value = null;
  open(file);
}
</script>

<template>
  <div>
    <button
      type="button"
      class="mb-4 text-body-sm font-medium text-gray-500 transition hover:text-gray-700"
      @click="chosen ? back() : emit('close')"
    >
      <i class="fas fa-arrow-left mr-1" aria-hidden="true"></i>
      {{ chosen ? "Choose another document" : "All tools" }}
    </button>

    <div class="rounded-lg border border-gray-200 bg-white p-6">
      <h2 class="text-h3 font-semibold text-gray-800">Rearrange pages</h2>
      <p class="mt-1 text-body-sm text-gray-500">
        Put the pages in order, turn the ones that came out sideways, and drop the ones you don't
        want. The document you started with is kept as a version.
      </p>

      <p v-if="error" role="alert" class="mt-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
        {{ error }}
      </p>

      <div v-if="result" class="mt-4 rounded-base border border-success-500 bg-success-50 p-4">
        <p class="text-body-sm font-semibold text-success-700">
          <i class="fas fa-check mr-1" aria-hidden="true"></i>Saved
        </p>
        <p class="mt-1 text-body font-medium text-gray-800">{{ result.name }}</p>
        <p class="mt-0.5 text-caption text-gray-600">
          {{ formatFileSize(result.size) }} · now version {{ result.version_number }} ·
          the previous one is still there under Details
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
            @click="editAgain"
          >
            Keep editing
          </button>
        </div>
      </div>

      <!-- Which document -->
      <template v-if="!chosen">
        <label for="pages-search" class="sr-only">Search your PDFs</label>
        <input
          id="pages-search"
          v-model="search"
          type="search"
          placeholder="Search by name"
          class="mb-3 mt-6 w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500 sm:max-w-sm"
        />

        <div v-if="loading" class="space-y-2">
          <div v-for="n in 4" :key="n" class="h-14 animate-pulse rounded-base bg-gray-100"></div>
        </div>

        <p v-else-if="!matches.length" class="rounded-base bg-gray-50 px-4 py-8 text-center text-body-sm text-gray-500">
          <template v-if="documents.length">Nothing matches that.</template>
          <template v-else>You have no PDFs yet.</template>
        </p>

        <ul v-else class="grid gap-2 sm:grid-cols-2">
          <li v-for="file in matches" :key="file.id">
            <button
              type="button"
              class="flex w-full items-center gap-3 rounded-base border border-gray-200 p-3 text-left transition hover:border-primary-300 hover:bg-primary-50"
              @click="open(file)"
            >
              <i class="fas fa-file-pdf text-error-500" aria-hidden="true"></i>
              <span class="min-w-0 flex-1">
                <span class="block truncate text-body-sm font-medium text-gray-800">{{ file.name }}</span>
                <span class="block text-caption text-gray-500">
                  {{ formatFileSize(file.size) }} · {{ formatRelativeDate(file.created_at) }}
                  <template v-if="file.version_number > 1"> · v{{ file.version_number }}</template>
                </span>
              </span>
              <i class="fas fa-chevron-right text-gray-300" aria-hidden="true"></i>
            </button>
          </li>
        </ul>
      </template>

      <!-- The pages themselves -->
      <template v-else>
        <div class="mt-6 flex flex-wrap items-center justify-between gap-3 border-b border-gray-100 pb-3">
          <div class="min-w-0">
            <p class="truncate text-body font-medium text-gray-800">{{ chosen.name }}</p>
            <p class="text-caption text-gray-500">
              <template v-if="loadingPages">
                <i class="fas fa-circle-notch fa-spin mr-1" aria-hidden="true"></i>
                Rendering {{ rendered.length }} of {{ pageCount || "…" }} pages
              </template>
              <template v-else>
                {{ pages.length }} of {{ pageCount }} pages kept
                <template v-if="removed.length"> · {{ removed.length }} removed</template>
              </template>
            </p>
          </div>

          <button
            v-if="changed && !loadingPages"
            type="button"
            class="text-body-sm font-medium text-gray-500 transition hover:text-gray-700"
            @click="reset"
          >
            Start over
          </button>
        </div>

        <div v-if="loadingPages && !pages.length" class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6">
          <div v-for="n in 6" :key="n" class="aspect-square animate-pulse rounded-base bg-gray-100"></div>
        </div>

        <p v-else-if="!pages.length" class="mt-6 rounded-base border-2 border-dashed border-gray-300 px-4 py-10 text-center text-body-sm text-gray-500">
          Every page has been removed. Put at least one back before saving.
        </p>

        <ol v-else class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6">
          <li
            v-for="(page, index) in pages"
            :key="page.number"
            draggable="true"
            class="rounded-base border border-gray-200 bg-white p-2 transition hover:border-primary-300"
            @dragstart="onDragStart(index)"
            @dragover.prevent
            @drop.prevent="onDrop(index)"
          >
            <div class="relative flex aspect-square items-center justify-center overflow-hidden rounded-sm bg-gray-50">
              <!-- A square box, so a quarter-turn always still fits inside it. -->
              <img
                :src="page.image"
                :alt="`Page ${page.number}`"
                class="max-h-full max-w-full object-contain shadow-sm transition-transform"
                :style="{ transform: `rotate(${page.rotation}deg)` }"
              />
              <span
                class="absolute left-1 top-1 rounded bg-gray-900/70 px-1.5 py-0.5 text-caption font-medium text-white"
              >
                {{ index + 1 }}
              </span>
            </div>

            <div class="mt-1.5 flex items-center justify-between">
              <span class="flex">
                <button
                  type="button"
                  :disabled="index === 0"
                  class="rounded p-1 text-gray-400 transition hover:bg-gray-100 disabled:opacity-30"
                  :aria-label="`Move page ${index + 1} earlier`"
                  @click="move(index, -1)"
                >
                  <i class="fas fa-chevron-left text-caption" aria-hidden="true"></i>
                </button>
                <button
                  type="button"
                  :disabled="index === pages.length - 1"
                  class="rounded p-1 text-gray-400 transition hover:bg-gray-100 disabled:opacity-30"
                  :aria-label="`Move page ${index + 1} later`"
                  @click="move(index, 1)"
                >
                  <i class="fas fa-chevron-right text-caption" aria-hidden="true"></i>
                </button>
              </span>

              <span class="flex">
                <button
                  type="button"
                  class="rounded p-1 text-gray-400 transition hover:bg-gray-100"
                  :aria-label="`Turn page ${index + 1} left`"
                  @click="rotate(page, -90)"
                >
                  <i class="fas fa-rotate-left text-caption" aria-hidden="true"></i>
                </button>
                <button
                  type="button"
                  class="rounded p-1 text-gray-400 transition hover:bg-gray-100"
                  :aria-label="`Turn page ${index + 1} right`"
                  @click="rotate(page, 90)"
                >
                  <i class="fas fa-rotate-right text-caption" aria-hidden="true"></i>
                </button>
                <button
                  type="button"
                  class="rounded p-1 text-error-500 transition hover:bg-error-50"
                  :aria-label="`Remove page ${index + 1}`"
                  @click="remove(index)"
                >
                  <i class="fas fa-xmark text-caption" aria-hidden="true"></i>
                </button>
              </span>
            </div>
          </li>
        </ol>

        <!-- Removed pages stay in sight, so dropping one by accident is not a
             thing you discover after saving. -->
        <section v-if="removed.length" class="mt-6">
          <h3 class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500">
            Removed — not in the saved document
          </h3>

          <ul class="flex flex-wrap gap-3">
            <li
              v-for="page in removed"
              :key="`removed-${page.number}`"
              class="w-28 rounded-base border border-dashed border-gray-300 bg-gray-50 p-2"
            >
              <div class="flex aspect-square items-center justify-center overflow-hidden rounded-sm">
                <img
                  :src="page.image"
                  :alt="`Removed page ${page.number}`"
                  class="max-h-full max-w-full object-contain opacity-40"
                />
              </div>
              <button
                type="button"
                class="mt-1 w-full rounded text-caption font-medium text-primary-600 transition hover:underline"
                @click="restore(page)"
              >
                Put page {{ page.number }} back
              </button>
            </li>
          </ul>
        </section>

        <div class="mt-6 flex flex-wrap items-center gap-3 border-t border-gray-100 pt-4">
          <button
            type="button"
            :disabled="!changed || saving || !pages.length || loadingPages"
            class="rounded-base gradient-main px-5 py-2.5 font-semibold text-white disabled:opacity-60"
            @click="save"
          >
            <span v-if="saving">
              <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Saving…
            </span>
            <span v-else>Save as a new version</span>
          </button>

          <p class="text-caption text-gray-500">
            <template v-if="!changed">Move, turn or remove a page to save a new version.</template>
            <template v-else>
              {{ pages.length }} page{{ pages.length === 1 ? "" : "s" }}, replacing
              {{ chosen.name }}. The version you started from stays.
            </template>
          </p>
        </div>
      </template>
    </div>
  </div>
</template>
