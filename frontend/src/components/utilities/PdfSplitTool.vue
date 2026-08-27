<script setup>
import { computed, onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import api from "@/api/client";
import { usePdfPages } from "@/composables/usePdfPages";
import { useToast } from "@/composables/useToast";
import { formatFileSize, formatRelativeDate } from "@/utils/formatting";

/**
 * Pulls a run of pages out of a PDF as a document of its own.
 *
 * The range is chosen by clicking the pages rather than by typing numbers,
 * because nobody knows which page the March statement starts on until they see
 * it. The original is left exactly as it was.
 */
const emit = defineEmits(["close"]);

const router = useRouter();
const toast = useToast();
const { pages, pageCount, loading: loadingPages, load } = usePdfPages();

const documents = ref([]);
const loading = ref(true);
const search = ref("");
const error = ref("");
const chosen = ref(null);
const from = ref(1);
const to = ref(1);
const saving = ref(false);
const result = ref(null);
// Which end of the range the next click sets. Without this, a click is
// ambiguous — "start at page 5" and "run as far as page 5" look identical.
const stage = ref("start");

const matches = computed(() => {
  const term = search.value.trim().toLowerCase();
  return documents.value.filter((f) => !term || f.name.toLowerCase().includes(term));
});

const count = computed(() => Math.max(0, to.value - from.value + 1));
const wholeDocument = computed(() => from.value === 1 && to.value === pageCount.value);

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

async function open(file) {
  chosen.value = file;
  result.value = null;
  error.value = "";

  try {
    await load(file.id);
    from.value = 1;
    to.value = Math.min(pageCount.value, 1);
    stage.value = "start";
  } catch (e) {
    error.value = e.userMessage;
    chosen.value = null;
  }
}

function back() {
  chosen.value = null;
  result.value = null;
}

/**
 * One click sets the first page, the next sets the last. Clicking before the
 * first page starts again from there rather than making a backwards range.
 */
function pick(number) {
  if (stage.value === "end" && number >= from.value) {
    to.value = number;
    stage.value = "start";
    return;
  }

  from.value = number;
  to.value = number;
  stage.value = "end";
}

function inRange(number) {
  return number >= from.value && number <= to.value;
}

async function run() {
  if (saving.value || !count.value) return;

  saving.value = true;
  error.value = "";

  try {
    const { data } = await api.post(
      `/files/${chosen.value.id}/split`,
      { from: from.value, to: to.value },
      { timeout: 120_000 },
    );

    result.value = data.file;
    toast.show({
      message: `Saved to ${data.file.folder?.name ?? "Top level"}`,
      detail: data.file.name,
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
      <h2 class="text-h3 font-semibold text-gray-800">Split a PDF</h2>
      <p class="mt-1 text-body-sm text-gray-500">
        Take a run of pages out as its own document. The one you started with is left alone.
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
            Take another piece out
          </button>
        </div>
      </div>

      <template v-if="!chosen">
        <label for="split-search" class="sr-only">Search your PDFs</label>
        <input
          id="split-search"
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
                </span>
              </span>
              <i class="fas fa-chevron-right text-gray-300" aria-hidden="true"></i>
            </button>
          </li>
        </ul>
      </template>

      <template v-else>
        <div class="mt-6 border-b border-gray-100 pb-3">
          <p class="truncate text-body font-medium text-gray-800">{{ chosen.name }}</p>
          <p class="text-caption text-gray-500">
            <template v-if="loadingPages">
              <i class="fas fa-circle-notch fa-spin mr-1" aria-hidden="true"></i>
              Rendering {{ pages.length }} of {{ pageCount || "…" }} pages
            </template>
            <template v-else-if="stage === 'start'">
              Click the first page of the piece you want
            </template>
            <template v-else>
              Now click the last page — or the same one again for a single page
            </template>
          </p>
        </div>

        <div v-if="loadingPages && !pages.length" class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6">
          <div v-for="n in 6" :key="n" class="aspect-square animate-pulse rounded-base bg-gray-100"></div>
        </div>

        <ul v-else class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6">
          <li v-for="page in pages" :key="page.number">
            <button
              type="button"
              :aria-pressed="inRange(page.number)"
              :class="[
                'block w-full rounded-base border-2 p-2 transition',
                inRange(page.number)
                  ? 'border-primary-500 bg-primary-50'
                  : 'border-gray-200 hover:border-gray-300',
              ]"
              @click="pick(page.number)"
            >
              <span class="flex aspect-square items-center justify-center overflow-hidden rounded-sm bg-gray-50">
                <img
                  :src="page.image"
                  :alt="`Page ${page.number}`"
                  class="max-h-full max-w-full object-contain shadow-sm"
                />
              </span>
              <span
                :class="[
                  'mt-1 block text-center text-caption font-medium',
                  inRange(page.number) ? 'text-primary-700' : 'text-gray-500',
                ]"
              >
                {{ page.number }}
                <template v-if="page.number === from && page.number === to"> · only page</template>
                <template v-else-if="page.number === from"> · first</template>
                <template v-else-if="page.number === to"> · last</template>
              </span>
            </button>
          </li>
        </ul>

        <div v-if="pages.length" class="mt-6 flex flex-wrap items-end gap-4 border-t border-gray-100 pt-4">
          <div>
            <label for="split-from" class="mb-1 block text-body-sm font-medium text-gray-700">
              First page
            </label>
            <input
              id="split-from"
              v-model.number="from"
              type="number"
              min="1"
              :max="pageCount"
              class="w-24 rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
            />
          </div>
          <div>
            <label for="split-to" class="mb-1 block text-body-sm font-medium text-gray-700">
              Last page
            </label>
            <input
              id="split-to"
              v-model.number="to"
              type="number"
              :min="from"
              :max="pageCount"
              class="w-24 rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
            />
          </div>

          <button
            type="button"
            :disabled="saving || count < 1 || to > pageCount || from < 1"
            class="rounded-base gradient-main px-5 py-2.5 font-semibold text-white disabled:opacity-60"
            @click="run"
          >
            <span v-if="saving">
              <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Saving…
            </span>
            <span v-else>
              Save {{ count }} page{{ count === 1 ? "" : "s" }} as a new document
            </span>
          </button>

          <p v-if="wholeDocument" class="text-caption text-warning-700">
            That is the whole document — you would get a copy of it.
          </p>
        </div>
      </template>
    </div>
  </div>
</template>
