<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import api from "@/api/client";
import RecordAttachmentPicker from "@/components/records/RecordAttachmentPicker.vue";
import RecordBreadcrumb from "@/components/records/RecordBreadcrumb.vue";
import RecordIcon from "@/components/records/RecordIcon.vue";
import RecordSecretInput from "@/components/records/RecordSecretInput.vue";
import ScanPageEditor from "@/components/utilities/ScanPageEditor.vue";
import { useVaultGate } from "@/composables/useVaultGate";
import { detectPage, encodingFor, loadImage, renderPage, toBlob, toCanvas } from "@/utils/scanner";

const route = useRoute();
const router = useRouter();
const vaultGate = useVaultGate();

const template = ref(null);
const loading = ref(true);
const saving = ref(false);
const error = ref("");
const attachmentIds = ref([]);

const form = ref({
  title: "",
  visibility: "private",
  data: {},
  secrets: {},
});

const secretFields = computed(() =>
  (template.value?.fields ?? []).filter((f) => f.kind === "secret"),
);

const editableFields = computed(() =>
  (template.value?.fields ?? []).filter((f) => f.kind !== "secret"),
);

/**
 * Some types name themselves from a field instead of a separate title — a
 * person is their name. The template says which field that is, because the
 * screen cannot tell: a passport also has a full name on it, and naming the
 * record after it would leave somebody with four records all called their own
 * name.
 */
const titleFieldKey = computed(() => template.value?.title_from ?? null);

const showTitleField = computed(() => !titleFieldKey.value);

/** Login and similar — one tight block, no documents section. */
const isCompactForm = computed(() => template.value?.type === "login");

/** The field that names the record, kept out of the grid so it can lead. */
const identityField = computed(() =>
  titleFieldKey.value ? editableFields.value.find((f) => f.key === titleFieldKey.value) : null,
);

/** Everything else, which pairs up two to a row. */
const gridFields = computed(() =>
  editableFields.value.filter((f) => f.key !== titleFieldKey.value),
);

/** What the header shows while you are still typing the name. */
const workingTitle = computed(
  () => (titleFieldKey.value ? form.value.data[titleFieldKey.value] : form.value.title) || "",
);

const compactSecrets = computed(() => isCompactForm.value || secretFields.value.length === 1);

const breadcrumbs = computed(() => [
  { label: "Register", to: { name: "household-register" } },
  { label: "Add", to: { name: "record-new" } },
  { label: template.value?.label ?? "…" },
]);

/* ------------------------------------------------------------- the scan */

/**
 * A document photographed on a phone, finished here.
 *
 * The phone is only the camera. The trimming, the PDF and the reading all
 * happen on this screen, because all three are things somebody has to look at
 * before they are worth anything — and this is the screen with room to look.
 */
const SCAN_QUALITY = 1800;
const PREVIEW_QUALITY = 800;

const scanToken = route.query.scan ?? "";
/** none · loading · trim · reading · done */
const scanStage = ref(scanToken ? "loading" : "none");
const scanPages = ref([]);
const scanPreset = ref("");
const scanError = ref("");
const pdfUrl = ref("");
/** The trimmed pages, kept to check the form against. */
const scanPreviews = ref([]);

// The loaded photographs. Outside Vue: an image behind a reactive proxy is
// re-wrapped on every canvas read, which is ruinous mid-drag.
const originals = new Map();

const scanning = computed(() => ["loading", "trim", "reading"].includes(scanStage.value));

/** Fields read off a scanned document, waiting to be checked. */
const fromScan = ref(null);

/** Fields the document itself vouches for, by check digit or by agreeing twice. */
const confirmedByDocument = computed(() => new Set(fromScan.value?.verified ?? []));

async function loadHeldScan() {
  try {
    const { data } = await api.get(`/scans/${scanToken}/status`);
    const held = data.receipt?.pages ?? [];
    if (!held.length) throw new Error("nothing waiting");

    scanPreset.value = data.receipt.preset || "other";

    for (const page of held) {
      const image = await loadImage(await fetchHeldPage(page.id));
      originals.set(page.id, image);

      scanPages.value.push({
        id: page.id,
        rotation: 0,
        // Detection runs small: it is looking for the shape of a page, and a
        // 12MP scan of it costs seconds for no better answer.
        corners: detectPage(toCanvas(image, { maxDimension: 900 })),
        filter: "document",
        brightness: 0,
        contrast: 0,
      });
    }

    scanStage.value = "trim";
  } catch (e) {
    scanError.value =
      e.userMessage ?? "That scan is no longer waiting. Take the photo again from your phone.";
    scanStage.value = "none";
  }
}

async function fetchHeldPage(id) {
  const { data } = await api.get(`/document_captures/page/${encodeURIComponent(id)}`, {
    responseType: "blob",
  });

  return data;
}

function onPageChange(index, change) {
  scanPages.value[index] = { ...scanPages.value[index], ...change };
}

function applyLookToAll(index) {
  const { filter, brightness, contrast } = scanPages.value[index];

  scanPages.value = scanPages.value.map((page) => ({ ...page, filter, brightness, contrast }));
}

/**
 * The one place the pages become a document: trimmed as shown, bound into a
 * PDF, and read. The PDF that gets attached is the PDF that was read, so what
 * the form says came from what is on the record.
 */
async function trimAndRead() {
  scanStage.value = "reading";
  scanError.value = "";

  try {
    const form = new FormData();

    for (const [index, page] of scanPages.value.entries()) {
      const encoding = encodingFor(page.filter);
      const blob = await toBlob(renderPage(originals.get(page.id), page, SCAN_QUALITY), encoding);

      form.append("pages[]", blob, `page-${index + 1}.${encoding.extension}`);

      // The same page again, small. What goes beside the form has to be the
      // page as trimmed, not the photograph it came from — and a picture shows
      // in every browser, where an embedded PDF is at the mercy of a viewer.
      scanPreviews.value.push(
        renderPage(originals.get(page.id), page, PREVIEW_QUALITY).toDataURL("image/jpeg", 0.82),
      );
    }

    form.append("preset", scanPreset.value);

    // Reading a photographed page is OCR, which is slow and is meant to be.
    const { data } = await api.post("/document_captures", form, { timeout: 180_000 });

    applySuggestion(data);
    scanStage.value = "done";
    releaseOriginals();
    if (data.file?.id) showPdf(data.file.id);
  } catch (e) {
    scanError.value = e.userMessage;
    scanStage.value = "trim";
  }
}

function applySuggestion(suggestion) {
  fromScan.value = suggestion;

  Object.entries(suggestion.fields ?? {}).forEach(([key, value]) => {
    if (template.value.fields.some((f) => f.key === key)) form.value.data[key] = value;
  });

  if (suggestion.title && showTitleField.value) form.value.title = suggestion.title;
  if (suggestion.file?.id) attachmentIds.value = [suggestion.file.id];
}

/** The PDF that was built and read, for opening in full. */
async function showPdf(fileId) {
  try {
    const { data } = await api.get(`/files/${fileId}/content`, { responseType: "blob" });
    pdfUrl.value = URL.createObjectURL(data);
  } catch {
    // The pages are already on screen and the PDF is already attached; only
    // the "open it full size" link is lost.
  }
}

function releaseOriginals() {
  originals.clear();
  scanPages.value = [];
}

onBeforeUnmount(() => {
  releaseOriginals();
  if (pdfUrl.value) URL.revokeObjectURL(pdfUrl.value);
});

onMounted(async () => {
  try {
    const { data } = await api.get("/record_templates");
    const match = data.templates.find((t) => t.type === route.params.type);
    if (!match) {
      router.replace({ name: "record-new" });
      return;
    }
    template.value = match;
    form.value.data = Object.fromEntries(
      match.fields.filter((f) => f.kind !== "secret").map((f) => [f.key, ""]),
    );
    form.value.secrets = Object.fromEntries(
      match.fields.filter((f) => f.kind === "secret").map((f) => [f.key, ""]),
    );

    if (scanToken) loadHeldScan();
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
});

function inputType(field) {
  // type="url" rejects bare domains like "netflix.com" and blocks form submit silently.
  if (field.kind === "url") return "text";
  if (field.kind === "date" || field.kind === "expiry") return "date";
  if (field.kind === "email") return "email";
  return "text";
}

function normalizeData() {
  const data = { ...form.value.data };
  for (const field of editableFields.value) {
    if (field.kind !== "url") continue;
    const raw = data[field.key]?.trim();
    if (raw && !/^https?:\/\//i.test(raw)) {
      data[field.key] = `https://${raw}`;
    }
  }
  return data;
}

function resolvedTitle() {
  const manual = form.value.title.trim();
  if (manual) return manual;
  const key = titleFieldKey.value;
  if (key) {
    const fromField = form.value.data[key]?.trim();
    if (fromField) return fromField;
  }
  return template.value?.title_hint ?? template.value?.label ?? "Untitled";
}

function canSave() {
  if (showTitleField.value && !form.value.title.trim()) return false;
  if (titleFieldKey.value && !form.value.data[titleFieldKey.value]?.trim()) return false;
  return true;
}

async function save() {
  if (!template.value || !canSave()) return;

  const hasSecrets = secretFields.value.some((f) => form.value.secrets[f.key]?.trim());
  if (hasSecrets && !(await vaultGate.ensureUnlocked())) {
    error.value = "Set up or unlock your private section to save the password.";
    return;
  }

  saving.value = true;
  error.value = "";
  try {
    const payload = {
      record: {
        record_type: template.value.type,
        title: resolvedTitle(),
        visibility: form.value.visibility,
        data: normalizeData(),
      },
      attachment_ids: attachmentIds.value,
    };

    if (hasSecrets) {
      payload.secrets = Object.fromEntries(
        secretFields.value
          .filter((f) => form.value.secrets[f.key]?.trim())
          .map((f) => [f.key, form.value.secrets[f.key].trim()]),
      );
    }

    const { data } = await api.post("/records", payload);
    router.push({ name: "record", params: { id: data.record.id } });
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <section :class="['mx-auto', pdfUrl || scanning ? 'max-w-7xl' : 'max-w-5xl']">
    <RecordBreadcrumb :crumbs="breadcrumbs" />

    <div v-if="loading" class="space-y-4">
      <div class="h-10 w-40 animate-pulse rounded-base bg-gray-100"></div>
      <div class="h-48 animate-pulse rounded-base bg-gray-100"></div>
    </div>

    <template v-else-if="template">
      <!-- Straighten it first. Nothing is read, and nothing is filed, until
           the pages look like the document rather than like a photograph of a
           table with a document on it. -->
      <section v-if="scanning">
        <header class="flex flex-wrap items-end justify-between gap-4 border-b border-gray-200 pb-5">
          <div>
            <p class="text-caption uppercase tracking-wider text-gray-500">
              New {{ template.label.toLowerCase() }}
            </p>
            <h1 class="mt-1 text-h2 font-bold text-gray-800">Straighten the scan</h1>
            <p class="mt-1 text-body-sm text-gray-500">
              Drag the corners onto the edges of the document. It becomes a PDF, and the PDF is
              what gets read.
            </p>
          </div>

          <div class="flex shrink-0 items-center gap-3">
            <RouterLink
              :to="{ name: 'household-register' }"
              class="text-body-sm font-medium text-gray-600 hover:text-gray-800"
            >
              Cancel
            </RouterLink>
            <button
              type="button"
              :disabled="scanStage !== 'trim'"
              class="rounded-base bg-primary-600 px-4 py-2 text-body-sm font-medium text-white transition hover:bg-primary-700 disabled:opacity-50"
              @click="trimAndRead"
            >
              <span v-if="scanStage === 'reading'">
                <i class="fas fa-circle-notch fa-spin mr-1.5" aria-hidden="true"></i>Reading…
              </span>
              <span v-else>Trim and read</span>
            </button>
          </div>
        </header>

        <p
          v-if="scanError"
          role="alert"
          class="mt-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
        >
          {{ scanError }}
        </p>

        <p v-if="scanStage === 'loading'" class="mt-8 text-center text-body text-gray-500">
          <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>
          Fetching what your phone sent…
        </p>

        <p v-else-if="scanStage === 'reading'" class="mt-8 text-center text-body text-gray-500">
          <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>
          Building the PDF and reading it. This takes a moment.
        </p>

        <div v-else class="mt-6 space-y-4">
          <ScanPageEditor
            v-for="(page, index) in scanPages"
            :key="page.id"
            :page="page"
            :image="originals.get(page.id)"
            :index="index"
            :total="scanPages.length"
            @change="onPageChange(index, $event)"
            @apply-to-all="applyLookToAll(index)"
          />
        </div>
      </section>

      <form v-else @submit.prevent="save">
        <!-- The same header the record will have once it exists, filled in as
             you type. You are naming a thing, not completing a field. -->
        <header class="flex flex-wrap items-start justify-between gap-4 border-b border-gray-200 pb-5">
          <div class="flex min-w-0 flex-1 items-start gap-4">
            <RecordIcon
              :title="workingTitle"
              :website="form.data.website ?? ''"
              :type-icon="template.icon"
              size="lg"
              class="mt-1"
            />
            <div class="min-w-0 flex-1">
              <p class="text-caption uppercase tracking-wider text-gray-500">{{ template.label }}</p>
              <label :for="identityField ? `field-${identityField.key}` : 'record-title'" class="sr-only">
                {{ identityField ? identityField.label : "Title" }}
              </label>
              <input
                v-if="identityField"
                :id="`field-${identityField.key}`"
                v-model="form.data[identityField.key]"
                type="text"
                required
                autofocus
                :placeholder="template.title_hint"
                class="mt-1 w-full border-b-2 border-gray-200 bg-transparent pb-1 text-h2 font-bold text-gray-800 outline-none transition placeholder:font-normal placeholder:text-gray-300 focus:border-primary-400"
              />
              <input
                v-else
                id="record-title"
                v-model="form.title"
                type="text"
                required
                autofocus
                :placeholder="template.title_hint"
                class="mt-1 w-full border-b-2 border-gray-200 bg-transparent pb-1 text-h2 font-bold text-gray-800 outline-none transition placeholder:font-normal placeholder:text-gray-300 focus:border-primary-400"
              />
              <p v-if="identityField?.hint" class="mt-1 text-caption text-gray-500">
                {{ identityField.hint }}
              </p>
            </div>
          </div>

          <div class="flex shrink-0 items-center gap-3">
            <RouterLink
              :to="{ name: 'household-register' }"
              class="text-body-sm font-medium text-gray-600 hover:text-gray-800"
            >
              Cancel
            </RouterLink>
            <button
              type="submit"
              :disabled="saving || !canSave()"
              class="rounded-base bg-primary-600 px-4 py-2 text-body-sm font-medium text-white transition hover:bg-primary-700 disabled:opacity-50"
            >
              {{ saving ? "Saving…" : "Save" }}
            </button>
          </div>
        </header>

        <p v-if="error" role="alert" class="mt-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
          {{ error }}
        </p>

        <!-- Read off a scan. Nothing is saved until it has been looked at. -->
        <div
          v-if="fromScan"
          class="mt-4 flex flex-wrap items-center gap-x-3 gap-y-1 rounded-base border border-primary-200 bg-primary-50 px-4 py-3 text-body-sm text-primary-800"
        >
          <span>
            <i class="fas fa-wand-magic-sparkles mr-1.5" aria-hidden="true"></i>
            Filled in from your scan — check it and save.
          </span>
          <span v-if="confirmedByDocument.size" class="text-caption text-primary-700">
            {{ confirmedByDocument.size }} of these the document checks against itself.
          </span>
          <span v-if="fromScan.file" class="text-caption text-primary-700">
            The scan is attached.
          </span>
        </div>

        <div
          :class="[
            'mt-6 grid gap-x-10 gap-y-8',
            scanPreviews.length
              ? 'lg:grid-cols-[minmax(0,1fr)_26rem]'
              : 'lg:grid-cols-[minmax(0,1fr)_18rem]',
          ]"
        >
          <div class="min-w-0 space-y-6">
            <!-- Short facts pair up; prose gets a row to itself. -->
            <div class="grid gap-x-6 gap-y-4 sm:grid-cols-2">
              <div
                v-for="field in gridFields"
                :key="field.key"
                :class="field.kind === 'multiline' ? 'sm:col-span-2' : ''"
              >
                <label :for="`field-${field.key}`" class="mb-1 block text-body-sm font-medium text-gray-700">
                  {{ field.label }}
                </label>
                <textarea
                  v-if="field.kind === 'multiline'"
                  :id="`field-${field.key}`"
                  v-model="form.data[field.key]"
                  rows="3"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
                ></textarea>
                <input
                  v-else
                  :id="`field-${field.key}`"
                  v-model="form.data[field.key]"
                  :type="inputType(field)"
                  :inputmode="field.kind === 'url' ? 'url' : undefined"
                  :placeholder="field.kind === 'url' ? 'netflix.com' : undefined"
                  :class="[
                    'w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500',
                    ['reference', 'number'].includes(field.kind) ? 'font-mono' : '',
                  ]"
                />
                <p
                  v-if="confirmedByDocument.has(field.key)"
                  class="mt-1 text-caption text-success-700"
                >
                  <i class="fas fa-check mr-1" aria-hidden="true"></i>The document checks this
                  against itself
                </p>
                <p v-else-if="field.hint" class="mt-1 text-caption text-gray-500">{{ field.hint }}</p>
              </div>
            </div>

            <!-- Encrypted, and it looks it. -->
            <fieldset v-if="secretFields.length" class="rounded-base border border-gray-200 bg-gray-50 p-4">
              <legend class="px-1 text-body-sm font-medium text-gray-700">
                <i class="fas fa-lock mr-1.5 text-gray-400" aria-hidden="true"></i>
                {{ secretFields.length === 1 ? secretFields[0].label : "Passwords" }}
              </legend>
              <p class="mb-3 text-caption text-gray-500">
                Encrypted with your private section passphrase. You'll be asked to unlock when you save.
              </p>
              <div class="space-y-4">
                <RecordSecretInput
                  v-for="field in secretFields"
                  :key="field.key"
                  :field="field"
                  v-model="form.secrets[field.key]"
                />
              </div>
            </fieldset>
          </div>

          <aside class="space-y-8 lg:border-l lg:border-gray-200 lg:pl-8">
            <!-- The document the fields were read off, to check them against. -->
            <div v-if="scanPreviews.length" class="lg:sticky lg:top-4">
              <div class="mb-3 flex items-baseline justify-between">
                <h2 class="text-caption uppercase tracking-wider text-gray-500">The scan</h2>
                <a
                  v-if="pdfUrl"
                  :href="pdfUrl"
                  target="_blank"
                  rel="noopener"
                  class="text-caption font-medium text-primary-600 hover:underline"
                >
                  Open the PDF
                </a>
              </div>
              <div class="max-h-[34rem] space-y-3 overflow-y-auto rounded-base border border-gray-200 bg-gray-50 p-3">
                <img
                  v-for="(preview, index) in scanPreviews"
                  :key="index"
                  :src="preview"
                  :alt="`Page ${index + 1} of the scan`"
                  class="w-full rounded-sm shadow-sm"
                />
              </div>
            </div>

            <div v-if="!isCompactForm">
              <h2 class="mb-3 text-caption uppercase tracking-wider text-gray-500">Documents</h2>
              <RecordAttachmentPicker v-model="attachmentIds" :visibility="form.visibility" />
            </div>

            <div>
              <label for="record-visibility" class="mb-2 block text-caption uppercase tracking-wider text-gray-500">
                Who can see it
              </label>
              <select
                id="record-visibility"
                v-model="form.visibility"
                class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
              >
                <option value="private">Just me</option>
                <option value="family">My family</option>
              </select>
            </div>
          </aside>
        </div>
      </form>
    </template>
  </section>
</template>
