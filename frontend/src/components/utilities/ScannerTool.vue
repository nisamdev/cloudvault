<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import api from "@/api/client";
import { useAuthStore } from "@/stores/auth";
import { useLibraryStore } from "@/stores/library";
import { useToast } from "@/composables/useToast";
import { formatFileSize } from "@/utils/formatting";
import {
  QUALITIES,
  detectPage,
  encodingFor,
  loadImage,
  renderPage,
  toBlob,
  toCanvas,
} from "@/utils/scanner";
import ScanPageEditor from "@/components/utilities/ScanPageEditor.vue";
import VaultImagePicker from "@/components/utilities/VaultImagePicker.vue";

/**
 * Photographs in, a document out.
 *
 * The work happens in the browser — cropping, straightening and the scanned
 * look — and only the finished pages are sent. That is what lets the preview be
 * the truth rather than a guess, and it keeps a pile of full-resolution photos
 * off the wire when only the trimmed page is wanted.
 */
const emit = defineEmits(["close"]);

const router = useRouter();
const auth = useAuthStore();
const library = useLibraryStore();
const toast = useToast();

/**
 * The originals, out of Vue's hands. An <img> is not state to be diffed, and
 * these are the largest objects on the page.
 */
const originals = new Map();

const pages = ref([]);
const activeId = ref(null);
const adding = ref(false);
const addingProgress = ref("");
const error = ref("");
const picking = ref(false);
const dropping = ref(false);

// Output
const output = ref("pdf");
const quality = ref(1800);
const pageSize = ref("auto");
const orientation = ref("auto");
const margin = ref("small");
const documentName = ref("");
const destination = ref("");
const visibility = ref("private");

const saving = ref(false);
const savingStep = ref("");
const result = ref(null);

const cameraInput = ref(null);
const fileInput = ref(null);

let thumbTimer = null;

const activePage = computed(() => pages.value.find((page) => page.id === activeId.value) ?? null);
const activeIndex = computed(() => pages.value.findIndex((page) => page.id === activeId.value));
const activeImage = computed(() => (activePage.value ? originals.get(activePage.value.id) : null));

const destinationName = computed(() => {
  if (!destination.value) return "Top level";
  return library.folders.find((f) => String(f.id) === String(destination.value))?.name ?? "Top level";
});

const defaultName = computed(
  () => `Scan ${new Date().toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" })}`,
);

onMounted(() => {
  if (!library.folders.length) library.fetchFolders();
});

onBeforeUnmount(() => {
  clearTimeout(thumbTimer);
  originals.clear();
});

/* ------------------------------------------------------------ adding pages */

function pickFiles(event) {
  const chosen = Array.from(event.target.files ?? []).map((file) => ({ blob: file, name: file.name }));
  event.target.value = "";
  addPages(chosen);
}

function onDrop(event) {
  event.preventDefault();
  dropping.value = false;

  const dropped = Array.from(event.dataTransfer?.files ?? [])
    .filter((file) => file.type.startsWith("image/"))
    .map((file) => ({ blob: file, name: file.name }));

  if (dropped.length) addPages(dropped);
}

/**
 * Every new page arrives already cropped to the app's best guess at where the
 * document is. Starting from the whole photo would mean everyone drags four
 * corners on every page; starting from a guess means most people drag none.
 */
async function addPages(items) {
  if (!items.length) return;

  adding.value = true;
  error.value = "";

  try {
    for (const [index, item] of items.entries()) {
      addingProgress.value = items.length > 1 ? `Reading ${index + 1} of ${items.length}…` : "Reading…";
      await yieldToBrowser();

      let image;
      try {
        image = await loadImage(item.blob);
      } catch {
        error.value = `${item.name} isn't an image we can read.`;
        continue;
      }

      const id = `${Date.now()}-${index}-${Math.random().toString(36).slice(2, 8)}`;
      const page = {
        id,
        name: item.name,
        rotation: 0,
        corners: detectPage(toCanvas(image, { maxDimension: 900 })),
        filter: pages.value.at(-1)?.filter ?? "document",
        brightness: 0,
        contrast: 0,
        thumb: "",
      };

      originals.set(id, image);
      pages.value.push(page);
      page.thumb = renderThumb(page);
    }

    if (!activeId.value && pages.value.length) activeId.value = pages.value[0].id;
  } finally {
    adding.value = false;
    addingProgress.value = "";
  }
}

function removePage(page) {
  originals.delete(page.id);
  pages.value = pages.value.filter((p) => p.id !== page.id);

  if (activeId.value === page.id) activeId.value = pages.value[0]?.id ?? null;
}

function movePage(index, delta) {
  const target = index + delta;
  if (target < 0 || target >= pages.value.length) return;

  const next = [...pages.value];
  [next[index], next[target]] = [next[target], next[index]];
  pages.value = next;
}

function startOver() {
  originals.clear();
  pages.value = [];
  activeId.value = null;
  result.value = null;
}

/* ---------------------------------------------------------------- editing */

function patchActive(patch) {
  const page = activePage.value;
  if (!page) return;

  Object.assign(page, patch);
  scheduleThumb(page);
}

function applyLookToAll() {
  const source = activePage.value;
  if (!source) return;

  for (const page of pages.value) {
    if (page.id === source.id) continue;

    page.filter = source.filter;
    page.brightness = source.brightness;
    page.contrast = source.contrast;
    page.thumb = renderThumb(page);
  }

  toast.show({ message: "Applied to every page", detail: "Each page keeps its own crop." });
}

/** Small enough to be cheap, so it can be redone whenever a control moves. */
function renderThumb(page) {
  const image = originals.get(page.id);
  if (!image) return "";

  try {
    return renderPage(image, page, 200).toDataURL("image/jpeg", 0.7);
  } catch {
    return "";
  }
}

function scheduleThumb(page) {
  clearTimeout(thumbTimer);
  thumbTimer = setTimeout(() => {
    page.thumb = renderThumb(page);
  }, 350);
}

/* ----------------------------------------------------------------- saving */

/** Lets the browser paint the progress line before the next page blocks it. */
function yieldToBrowser() {
  return new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
}

async function save() {
  if (!pages.value.length || saving.value) return;

  saving.value = true;
  error.value = "";
  result.value = null;

  try {
    const rendered = [];

    for (const [index, page] of pages.value.entries()) {
      savingStep.value = `Rendering page ${index + 1} of ${pages.value.length}…`;
      await yieldToBrowser();

      // PNG was asked for explicitly, so it is honoured whatever the filter
      // would have chosen for itself.
      const encoding =
        output.value === "png" ? { type: "image/png", extension: "png" } : encodingFor(page.filter);

      const canvas = renderPage(originals.get(page.id), page, quality.value);
      rendered.push({ blob: await toBlob(canvas, encoding), extension: encoding.extension });
    }

    savingStep.value = output.value === "pdf" ? "Building the document…" : "Uploading…";
    result.value = output.value === "pdf" ? await saveAsPdf(rendered) : await saveAsImages(rendered);

    announce();
  } catch (e) {
    error.value = e.userMessage ?? e.message;
  } finally {
    saving.value = false;
    savingStep.value = "";
  }
}

async function saveAsPdf(rendered) {
  const base = documentName.value.trim() || defaultName.value;
  const form = new FormData();

  rendered.forEach((page, index) => {
    form.append("pages[]", page.blob, `page-${index + 1}.${page.extension}`);
  });
  form.append("name", base);
  form.append("page_size", pageSize.value);
  form.append("orientation", orientation.value);
  form.append("margin", margin.value);
  form.append("visibility", visibility.value);
  if (destination.value) form.append("folder_id", destination.value);

  const { data } = await api.post("/utilities/images_to_pdf", form, { timeout: 180_000 });

  return { files: [data.file], kind: "pdf" };
}

async function saveAsImages(rendered) {
  const base = documentName.value.trim() || defaultName.value;
  const saved = [];

  for (const [index, page] of rendered.entries()) {
    savingStep.value = `Uploading ${index + 1} of ${rendered.length}…`;

    const name = rendered.length === 1 ? `${base}.png` : `${base} (${index + 1}).png`;
    const form = new FormData();
    form.append("file", page.blob, name);
    form.append("visibility", visibility.value);
    if (destination.value) form.append("folder_id", destination.value);

    const { data } = await api.post("/files", form, { timeout: 180_000 });
    saved.push(data.file);
  }

  return { files: saved, kind: "png" };
}

function announce() {
  const files = result.value.files;
  const where = files[0].folder?.name ?? "Top level";

  toast.show({
    message: `Saved to ${where}`,
    detail: files.length === 1 ? files[0].name : `${files.length} pages`,
    actionLabel: "Show me",
    action: openResult,
  });
}

function openResult() {
  const file = result.value?.files?.[0];
  if (!file) return;

  router.push({
    name: file.file_type === "image" ? "images" : "dashboard",
    query: { show: file.id, folder: file.folder?.id ?? "" },
  });
}

const totalSaved = computed(() =>
  (result.value?.files ?? []).reduce((sum, file) => sum + (file.size ?? 0), 0),
);
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
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 class="text-h3 font-semibold text-gray-800">Scan &amp; make a PDF</h2>
          <p class="mt-1 text-body-sm text-gray-500">
            Photograph a document, trim it to the page, and save it as a scan — one PDF or separate
            images.
          </p>
        </div>

        <button
          v-if="pages.length"
          type="button"
          class="text-body-sm font-medium text-gray-500 transition hover:text-error-600"
          @click="startOver"
        >
          Start again
        </button>
      </div>

      <p v-if="error" role="alert" class="mt-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
        {{ error }}
      </p>

      <!-- What was made, kept on screen: a toast is a nicety, this is the record -->
      <div v-if="result" class="mt-4 rounded-base border border-success-500 bg-success-50 p-4">
        <p class="text-body-sm font-semibold text-success-700">
          <i class="fas fa-check mr-1" aria-hidden="true"></i>Saved
        </p>
        <ul class="mt-1 space-y-0.5">
          <li v-for="file in result.files" :key="file.id" class="text-body font-medium text-gray-800">
            {{ file.name }}
          </li>
        </ul>
        <p class="mt-0.5 text-caption text-gray-600">
          {{ formatFileSize(totalSaved) }} · saved in
          <strong>{{ result.files[0].folder?.name ?? "Top level" }}</strong>
          · {{ visibility === "family" ? "shared with your family" : "only you can see it" }}
        </p>

        <div class="mt-3 flex flex-wrap gap-2">
          <button
            type="button"
            class="rounded-base bg-success-700 px-4 py-2 text-body-sm font-semibold text-white transition hover:opacity-90"
            @click="openResult"
          >
            Open it
          </button>
          <button
            type="button"
            class="rounded-base border border-gray-300 bg-white px-4 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
            @click="startOver"
          >
            Scan something else
          </button>
        </div>
      </div>

      <!-- Adding -->
      <div
        :class="[
          'mt-6 rounded-lg border-2 border-dashed p-6 text-center transition',
          dropping ? 'border-primary-500 bg-primary-50' : 'border-gray-300',
        ]"
        @dragover.prevent="dropping = true"
        @dragleave="dropping = false"
        @drop="onDrop"
      >
        <div class="flex flex-wrap items-center justify-center gap-3">
          <button
            type="button"
            class="rounded-base gradient-main px-4 py-2 text-body-sm font-semibold text-white"
            @click="fileInput.click()"
          >
            <i class="fas fa-images mr-2" aria-hidden="true"></i>Choose photos
          </button>
          <button
            type="button"
            class="rounded-base border border-gray-300 px-4 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
            @click="cameraInput.click()"
          >
            <i class="fas fa-camera mr-2" aria-hidden="true"></i>Use the camera
          </button>
          <button
            type="button"
            class="rounded-base border border-gray-300 px-4 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
            @click="picking = true"
          >
            <i class="fas fa-cloud mr-2" aria-hidden="true"></i>From your photos
          </button>
        </div>

        <p class="mt-3 text-caption text-gray-500">
          <span v-if="adding">{{ addingProgress }}</span>
          <span v-else>…or drop photos here. Nothing is uploaded until you save.</span>
        </p>

        <input
          ref="fileInput"
          type="file"
          accept="image/*"
          multiple
          class="sr-only"
          aria-label="Choose photos to scan"
          @change="pickFiles"
        />
        <input
          ref="cameraInput"
          type="file"
          accept="image/*"
          capture="environment"
          class="sr-only"
          aria-label="Take a photo of the document"
          @change="pickFiles"
        />
      </div>

      <div v-if="pages.length" class="mt-6 grid gap-6 lg:grid-cols-[16rem_1fr]">
        <!-- The pages, in order -->
        <div>
          <h3 class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500">
            {{ pages.length }} page{{ pages.length === 1 ? "" : "s" }}
          </h3>

          <ol class="max-h-[38rem] space-y-2 overflow-y-auto pr-1">
            <li v-for="(page, index) in pages" :key="page.id">
              <div
                :class="[
                  'flex items-center gap-2 rounded-base border p-2 transition',
                  page.id === activeId ? 'border-primary-500 bg-primary-50' : 'border-gray-200',
                ]"
              >
                <button
                  type="button"
                  class="flex min-w-0 flex-1 items-center gap-2 text-left"
                  :aria-current="page.id === activeId ? 'true' : undefined"
                  @click="activeId = page.id"
                >
                  <img
                    v-if="page.thumb"
                    :src="page.thumb"
                    alt=""
                    class="h-14 w-11 shrink-0 rounded-sm border border-gray-200 bg-white object-contain"
                  />
                  <span v-else class="h-14 w-11 shrink-0 animate-pulse rounded-sm bg-gray-100"></span>

                  <span class="min-w-0">
                    <span class="block text-body-sm font-medium text-gray-800">Page {{ index + 1 }}</span>
                    <span class="block truncate text-caption text-gray-500">{{ page.name }}</span>
                  </span>
                </button>

                <span class="flex shrink-0 flex-col">
                  <button
                    type="button"
                    :disabled="index === 0"
                    class="rounded p-1 text-gray-400 transition hover:bg-gray-200 disabled:opacity-30"
                    :aria-label="`Move page ${index + 1} earlier`"
                    @click="movePage(index, -1)"
                  >
                    <i class="fas fa-chevron-up text-caption" aria-hidden="true"></i>
                  </button>
                  <button
                    type="button"
                    :disabled="index === pages.length - 1"
                    class="rounded p-1 text-gray-400 transition hover:bg-gray-200 disabled:opacity-30"
                    :aria-label="`Move page ${index + 1} later`"
                    @click="movePage(index, 1)"
                  >
                    <i class="fas fa-chevron-down text-caption" aria-hidden="true"></i>
                  </button>
                  <button
                    type="button"
                    class="rounded p-1 text-error-500 transition hover:bg-error-50"
                    :aria-label="`Remove page ${index + 1}`"
                    @click="removePage(page)"
                  >
                    <i class="fas fa-xmark text-caption" aria-hidden="true"></i>
                  </button>
                </span>
              </div>
            </li>
          </ol>
        </div>

        <!-- The page being worked on -->
        <div class="min-w-0 space-y-6">
          <ScanPageEditor
            v-if="activePage && activeImage"
            :key="activePage.id"
            :page="activePage"
            :image="activeImage"
            :index="activeIndex"
            :total="pages.length"
            @change="patchActive"
            @apply-to-all="applyLookToAll"
          />

          <!-- Output -->
          <div class="rounded-lg border border-gray-200 bg-white p-4">
            <h3 class="mb-3 text-body font-semibold text-gray-800">Save it as</h3>

            <div class="grid gap-2 sm:grid-cols-2">
              <button
                v-for="option in [
                  { value: 'pdf', label: 'One PDF', icon: 'fa-file-pdf', hint: 'All the pages in one document' },
                  { value: 'png', label: 'PNG images', icon: 'fa-file-image', hint: 'One picture per page' },
                ]"
                :key="option.value"
                type="button"
                :aria-pressed="output === option.value"
                :class="[
                  'rounded-base border p-3 text-left transition',
                  output === option.value
                    ? 'border-primary-600 bg-primary-50'
                    : 'border-gray-300 hover:bg-gray-50',
                ]"
                @click="output = option.value"
              >
                <span class="block text-body-sm font-semibold text-gray-800">
                  <i :class="['fas', option.icon, 'mr-2 text-gray-400']" aria-hidden="true"></i>
                  {{ option.label }}
                </span>
                <span class="mt-0.5 block text-caption text-gray-500">{{ option.hint }}</span>
              </button>
            </div>

            <div class="mt-4 grid gap-4 sm:grid-cols-2">
              <div>
                <label for="scan-quality" class="mb-1 block text-body-sm font-medium text-gray-700">
                  Detail
                </label>
                <select
                  id="scan-quality"
                  v-model.number="quality"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
                >
                  <option v-for="option in QUALITIES" :key="option.value" :value="option.value">
                    {{ option.label }} — {{ option.hint }}
                  </option>
                </select>
              </div>

              <div v-if="output === 'pdf'">
                <label for="scan-page-size" class="mb-1 block text-body-sm font-medium text-gray-700">
                  Page size
                </label>
                <select
                  id="scan-page-size"
                  v-model="pageSize"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
                >
                  <option value="auto">Match the photo — no borders</option>
                  <option value="a4">A4</option>
                  <option value="letter">US Letter</option>
                  <option value="legal">US Legal</option>
                </select>
              </div>

              <div v-if="output === 'pdf' && pageSize !== 'auto'">
                <label for="scan-orientation" class="mb-1 block text-body-sm font-medium text-gray-700">
                  Orientation
                </label>
                <select
                  id="scan-orientation"
                  v-model="orientation"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
                >
                  <option value="auto">Follow each page</option>
                  <option value="portrait">Portrait</option>
                  <option value="landscape">Landscape</option>
                </select>
              </div>

              <div v-if="output === 'pdf'">
                <label for="scan-margin" class="mb-1 block text-body-sm font-medium text-gray-700">
                  Margin
                </label>
                <select
                  id="scan-margin"
                  v-model="margin"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
                >
                  <option value="none">None</option>
                  <option value="small">Small</option>
                  <option value="medium">Medium</option>
                  <option value="large">Large</option>
                </select>
              </div>
            </div>

            <hr class="my-4 border-gray-100" />

            <div class="grid gap-4 sm:grid-cols-2">
              <div>
                <label for="scan-name" class="mb-1 block text-body-sm font-medium text-gray-700">
                  Name
                </label>
                <input
                  id="scan-name"
                  v-model="documentName"
                  type="text"
                  :placeholder="defaultName"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
                />
              </div>

              <div>
                <label for="scan-destination" class="mb-1 block text-body-sm font-medium text-gray-700">
                  Save it in
                </label>
                <select
                  id="scan-destination"
                  v-model="destination"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
                >
                  <option value="">Top level</option>
                  <option v-for="folder in library.folders" :key="folder.id" :value="folder.id">
                    {{ folder.name }}
                  </option>
                </select>
              </div>

              <div class="sm:col-span-2">
                <label for="scan-visibility" class="mb-1 block text-body-sm font-medium text-gray-700">
                  Who can see it
                </label>
                <select
                  id="scan-visibility"
                  v-model="visibility"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
                >
                  <option value="private">Only me</option>
                  <option value="family" :disabled="!auth.canEdit">Share with my family</option>
                </select>
              </div>
            </div>

            <p class="mt-3 text-caption text-gray-500">
              {{ pages.length }} page{{ pages.length === 1 ? "" : "s" }} into
              <strong>{{ destinationName }}</strong
              >. The photos you started from are untouched.
            </p>

            <button
              type="button"
              :disabled="saving"
              class="mt-3 w-full rounded-base gradient-main py-2.5 font-semibold text-white disabled:opacity-60"
              @click="save"
            >
              <span v-if="saving">
                <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>{{ savingStep }}
              </span>
              <span v-else-if="output === 'pdf'">
                Save as one PDF
              </span>
              <span v-else>
                Save {{ pages.length }} PNG{{ pages.length === 1 ? "" : "s" }}
              </span>
            </button>
          </div>
        </div>
      </div>
    </div>

    <VaultImagePicker v-if="picking" @close="picking = false" @add="addPages" />
  </div>
</template>
