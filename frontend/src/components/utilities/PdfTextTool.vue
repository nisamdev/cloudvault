<script setup>
import { computed, onMounted, ref } from "vue";
import api from "@/api/client";
import { usePdfPages } from "@/composables/usePdfPages";
import { copyText } from "@/utils/clipboard";
import { formatFileSize, formatRelativeDate } from "@/utils/formatting";

/**
 * Reads a document — page image on the left, copyable text on the right.
 */
const emit = defineEmits(["close"]);

const {
  pages: pageImages,
  loading: loadingPages,
  load: loadPages,
  clear: clearPages,
} = usePdfPages();

const documents = ref([]);
const loading = ref(true);
const search = ref("");
const error = ref("");

const chosen = ref(null);
const reading = ref(false);
const result = ref(null);
const copied = ref("");

let copiedTimer = null;

const matches = computed(() => {
  const term = search.value.trim().toLowerCase();
  return documents.value.filter((f) => !term || f.name.toLowerCase().includes(term));
});

/** Page image + extracted text, matched by page number. */
const pairedPages = computed(() => {
  const texts = result.value?.pages ?? [];
  const imagesByNumber = Object.fromEntries(
    pageImages.value.map((page) => [page.number, page]),
  );

  if (texts.length) {
    return texts.map((page) => ({
      number: page.number,
      text: page.text || "",
      image: imagesByNumber[page.number]?.image ?? null,
    }));
  }

  return pageImages.value.map((page) => ({
    number: page.number,
    text: "",
    image: page.image,
  }));
});

const keyDetails = computed(() => result.value?.details ?? []);

const wholeText = computed(() => {
  const pages = (result.value?.pages ?? [])
    .map((page) => page.text)
    .filter(Boolean)
    .join("\n\n");
  if (!keyDetails.value.length) return pages;

  const header = keyDetails.value
    .map((detail) => `${detail.label}: ${detail.value}`)
    .join("\n");
  return pages ? `${header}\n\n${pages}` : header;
});

function panelText(page) {
  if (page.number !== 1 || !keyDetails.value.length) return page.text || "";

  const header = keyDetails.value
    .map((detail) => `${detail.label}: ${detail.value}`)
    .join("\n");
  const body = page.text || "";
  return body ? `${header}\n\n${body}` : header;
}

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

async function read(file) {
  chosen.value = file;
  result.value = null;
  clearPages();
  error.value = "";
  reading.value = true;

  try {
    const [textResponse] = await Promise.all([
      api.get(`/files/${file.id}/text`, { timeout: 180_000 }),
      loadPages(file.id, { size: "render" }).catch((e) => {
        error.value = e.userMessage;
      }),
    ]);
    result.value = textResponse.data;
  } catch (e) {
    error.value = e.userMessage;
    chosen.value = null;
    clearPages();
  } finally {
    reading.value = false;
  }
}

function back() {
  chosen.value = null;
  result.value = null;
  clearPages();
}

async function copy(value, token) {
  if (!value) return;

  const ok = await copyText(value);
  clearTimeout(copiedTimer);
  copied.value = ok ? token : "";

  if (!ok) {
    error.value = "Your browser wouldn't let the page use the clipboard. Select the text and copy it by hand.";
    return;
  }

  copiedTimer = setTimeout(() => (copied.value = ""), 2000);
}

function copyDetail(detail, index) {
  copy(`${detail.label}: ${detail.value}`, `detail-${index}`);
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
      {{ chosen ? "Read another document" : "All tools" }}
    </button>

    <div class="rounded-lg border border-gray-200 bg-white p-6">
      <h2 class="text-h3 font-semibold text-gray-800">Read a document</h2>
      <p class="mt-1 text-body-sm text-gray-500">
        See each page next to the text you can copy. Scans are read with OCR when there’s no text layer.
      </p>

      <p v-if="error" role="alert" class="mt-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
        {{ error }}
      </p>

      <template v-if="!chosen">
        <label for="text-search" class="sr-only">Search your PDFs</label>
        <input
          id="text-search"
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
              @click="read(file)"
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
        <div class="mt-6 flex flex-wrap items-start justify-between gap-3 border-b border-gray-100 pb-3">
          <div class="min-w-0">
            <p class="truncate text-body font-medium text-gray-800">{{ chosen.name }}</p>
            <p class="text-caption text-gray-500">
              <template v-if="reading || loadingPages">
                <i class="fas fa-circle-notch fa-spin mr-1" aria-hidden="true"></i>
                {{ reading ? "Reading text… scans can take a minute" : "Loading page pictures…" }}
              </template>
              <template v-else-if="result">
                {{ result.page_count }} page{{ result.page_count === 1 ? "" : "s" }}
                <template v-if="result.source === 'ocr'"> · read with OCR</template>
                <template v-if="result.truncated"> · only the first part was read</template>
              </template>
            </p>
          </div>

          <button
            v-if="result?.has_text"
            type="button"
            class="shrink-0 rounded-base border border-gray-300 px-3 py-1.5 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
            @click="copy(wholeText, 'all')"
          >
            <i
              :class="['fas mr-1.5', copied === 'all' ? 'fa-check text-success-600' : 'fa-copy']"
              aria-hidden="true"
            ></i>
            {{ copied === "all" ? "Copied" : "Copy all text" }}
          </button>
        </div>

        <div v-if="reading && !result" class="mt-4 space-y-2">
          <div v-for="n in 4" :key="n" class="h-40 animate-pulse rounded-base bg-gray-100"></div>
        </div>

        <template v-else-if="result">
          <p
            v-if="!result.has_text"
            class="mt-6 rounded-base border border-warning-500 bg-warning-50 p-4 text-body-sm text-gray-700"
          >
            <i class="fas fa-image mr-1.5 text-warning-600" aria-hidden="true"></i>
            Couldn’t pull clear text from this scan — the pages are still shown below.
          </p>

          <!-- One row per page: picture | copyable text -->
          <section class="mt-6 space-y-8">
            <article
              v-for="page in pairedPages"
              :key="page.number"
              class="grid gap-4 lg:grid-cols-2 lg:items-start"
            >
              <div class="overflow-hidden rounded-base border border-gray-200 bg-gray-50">
                <p class="border-b border-gray-200 px-3 py-1.5 text-caption font-medium text-gray-500">
                  Page {{ page.number }}
                </p>
                <img
                  v-if="page.image"
                  :src="page.image"
                  :alt="`Page ${page.number}`"
                  class="mx-auto max-h-[36rem] w-full object-contain"
                />
                <div
                  v-else-if="loadingPages"
                  class="flex h-48 items-center justify-center text-caption text-gray-400"
                >
                  <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Loading picture…
                </div>
                <div
                  v-else
                  class="flex h-48 items-center justify-center text-caption text-gray-400"
                >
                  No page preview
                </div>
              </div>

              <div class="flex min-h-0 flex-col rounded-base border border-gray-200">
                <div class="flex items-center justify-between gap-2 border-b border-gray-200 px-3 py-1.5">
                  <p class="text-caption font-medium text-gray-500">Text you can copy</p>
                  <button
                    v-if="panelText(page)"
                    type="button"
                    class="rounded-md px-2 py-1 text-caption font-medium text-gray-600 transition hover:bg-gray-100"
                    @click="copy(panelText(page), `page-${page.number}`)"
                  >
                    <i
                      :class="[
                        'fas mr-1',
                        copied === `page-${page.number}` ? 'fa-check text-success-600' : 'fa-copy',
                      ]"
                      aria-hidden="true"
                    ></i>
                    {{ copied === `page-${page.number}` ? "Copied" : "Copy" }}
                  </button>
                </div>

                <div class="max-h-[36rem] flex-1 overflow-auto bg-white">
                  <div
                    v-if="page.number === 1 && keyDetails.length"
                    class="space-y-2 border-b border-gray-100 px-3 py-3"
                  >
                    <p class="text-caption font-medium uppercase tracking-wide text-gray-500">
                      Key details
                    </p>
                    <ul class="space-y-2">
                      <li
                        v-for="(detail, i) in keyDetails"
                        :key="`${detail.label}-${i}`"
                        class="flex items-start gap-2"
                      >
                        <span class="min-w-0 flex-1">
                          <span class="block text-caption text-gray-500">{{ detail.label }}</span>
                          <span class="block break-words text-body-sm font-medium text-gray-800">
                            {{ detail.value }}
                          </span>
                        </span>
                        <button
                          type="button"
                          class="shrink-0 rounded-md p-1.5 text-gray-400 transition hover:bg-gray-100 hover:text-gray-700"
                          :aria-label="`Copy ${detail.label}`"
                          @click="copyDetail(detail, i)"
                        >
                          <i
                            :class="[
                              'fas',
                              copied === `detail-${i}` ? 'fa-check text-success-600' : 'fa-copy',
                            ]"
                            aria-hidden="true"
                          ></i>
                        </button>
                      </li>
                    </ul>
                  </div>

                  <pre
                    class="whitespace-pre-wrap p-3 text-body-sm text-gray-800 select-text"
                  >{{ page.text || "No text found on this page." }}</pre>
                </div>
              </div>
            </article>
          </section>
        </template>
      </template>
    </div>
  </div>
</template>
