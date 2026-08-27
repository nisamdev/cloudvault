<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import api from "@/api/client";
import RecordAttachmentPicker from "@/components/records/RecordAttachmentPicker.vue";
import RecordBreadcrumb from "@/components/records/RecordBreadcrumb.vue";
import RecordIcon from "@/components/records/RecordIcon.vue";
import RecordHolderPicker from "@/components/records/RecordHolderPicker.vue";
import RecordSecretInput from "@/components/records/RecordSecretInput.vue";
import DocumentSourcePicker from "@/components/records/DocumentSourcePicker.vue";
import ScanPageEditor from "@/components/utilities/ScanPageEditor.vue";
import { useVaultGate } from "@/composables/useVaultGate";
import { sectionCrumb, sectionFor } from "@/utils/recordSection";
import {
  FULL_FRAME,
  detectPage,
  encodingFor,
  loadImage,
  renderPage,
  toBlob,
  toCanvas,
} from "@/utils/scanner";

const route = useRoute();
const router = useRouter();
const vaultGate = useVaultGate();

const template = ref(null);
const loading = ref(true);
const saving = ref(false);
const error = ref("");
const attachmentIds = ref([]);
const heldById = ref(null);

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
  sectionCrumb(template.value?.group),
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
/** none · choosing · loading · trim · reading · done */
const scanStage = ref(scanToken ? "loading" : "none");
const scanPages = ref([]);
const scanPreset = ref("");
const scanError = ref("");
/** The read finished and found nothing worth putting in the form. */
const readNothing = ref(false);
const pdfUrl = ref("");
/** The trimmed pages, kept to check the form against. */
const scanPreviews = ref([]);
/** A file from the vault, when the document was chosen rather than photographed. */
const sourceFile = ref(null);
/** Whether that file carries real text, or is a picture of some. */
const sourceHasText = ref(false);
/** PDFs this form built. Reading again replaces one rather than adding another. */
const built = ref([]);
/** Which kind of document this form is, if a scanner knows how to read it. */
const readablePreset = ref(null);

// The loaded photographs. Outside Vue: an image behind a reactive proxy is
// re-wrapped on every canvas read, which is ruinous mid-drag.
const originals = new Map();

const scanning = computed(() =>
  ["choosing", "loading", "trim", "reading"].includes(scanStage.value),
);

/** Whether the pages are still exactly as they arrived. */
const untouched = computed(() =>
  scanPages.value.every(
    (page) =>
      !page.rotation &&
      page.filter === "original" &&
      (page.corners ?? FULL_FRAME).every((c, i) => c.x === FULL_FRAME[i].x && c.y === FULL_FRAME[i].y),
  ),
);

/**
 * A PDF that carries real text is read as it is — rendering it to a picture and
 * running OCR over that could only lose something. A scanned PDF has no such
 * advantage: it is a photograph, and it reads better cropped to the document
 * than left as a card in the middle of a sheet of A4.
 */
const readsOriginal = computed(
  () => sourceFile.value?.mime_type === "application/pdf" && sourceHasText.value && untouched.value,
);

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

/** Offer to read only where there is something that knows how to read it. */
async function findPreset(type) {
  try {
    const { data } = await api.get("/document_captures/presets");
    readablePreset.value = data.presets.find((preset) => preset.record_type === type) ?? null;
  } catch {
    // Without this the form is simply a form, which is what it was before.
  }
}

async function useFile(file) {
  sourceFile.value = file;
  sourceHasText.value = false;
  scanPreset.value = readablePreset.value?.key ?? "other";
  scanStage.value = "loading";
  scanError.value = "";
  scanPages.value = [];
  originals.clear();

  try {
    const isPdf = file.mime_type === "application/pdf";
    const sources = isPdf ? await renderedPdfPages(file.id) : [ await fileBlob(file.id) ];

    for (const [index, source] of sources.entries()) {
      const image = await loadImage(source);
      const id = `${file.id}-${index}`;
      originals.set(id, image);

      scanPages.value.push({
        id,
        rotation: 0,
        // A PDF page is already square on. A photograph is not, so it gets the
        // detector; the PDF starts whole and is only cropped if asked.
        corners: isPdf
          ? FULL_FRAME.map((corner) => ({ ...corner }))
          : detectPage(toCanvas(image, { maxDimension: 900 })),
        filter: isPdf ? "original" : "document",
        brightness: 0,
        contrast: 0,
      });
    }

    scanStage.value = "trim";
  } catch (e) {
    scanError.value = e.userMessage ?? "That file couldn't be opened.";
    scanStage.value = "choosing";
  }
}

async function fileBlob(id) {
  const { data } = await api.get(`/files/${id}/content`, { responseType: "blob" });

  return data;
}

async function renderedPdfPages(id) {
  // Rendered large: this is going to be cropped down to a card and read, and
  // the page-turning size loses the small print before OCR ever sees it.
  const { data } = await api.get(`/files/${id}/pages`, { params: { size: "read" } });
  sourceHasText.value = data.has_text_layer === true;

  return Promise.all(data.pages.map((page) => fetch(page.image).then((r) => r.blob())));
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
  readNothing.value = false;
  // Reading again replaces what is beside the form rather than adding to it.
  scanPreviews.value = [];

  try {
    const form = new FormData();
    form.append("preset", scanPreset.value);

    if (readsOriginal.value) {
      form.append("file_id", sourceFile.value.id);
    }

    for (const [index, page] of scanPages.value.entries()) {
      if (!readsOriginal.value) {
        const encoding = encodingFor(page.filter);
        const blob = await toBlob(renderPage(originals.get(page.id), page, SCAN_QUALITY), encoding);

        form.append("pages[]", blob, `page-${index + 1}.${encoding.extension}`);
      }

      // The same page again, small. What goes beside the form has to be the
      // page as trimmed, not the photograph it came from — and a picture shows
      // in every browser, where an embedded PDF is at the mercy of a viewer.
      scanPreviews.value.push(
        renderPage(originals.get(page.id), page, PREVIEW_QUALITY).toDataURL("image/jpeg", 0.82),
      );
    }

    // Reading a photographed page is OCR, which is slow and is meant to be.
    const { data } = await api.post("/document_captures", form, { timeout: 180_000 });

    applySuggestion(data);
    scanStage.value = "done";
    readNothing.value = Object.keys(data.fields ?? {}).length === 0;

    // Reading again after a better crop replaces the PDF from the last go.
    // Otherwise every attempt leaves another near-identical scan in My Files,
    // and the only one worth keeping is the one the form ends up using.
    if (data.file?.id && !readsOriginal.value) {
      const superseded = built.value.filter((id) => id !== data.file.id);
      built.value = [data.file.id];
      superseded.forEach(discard);
    }
    // The pages are kept, not released: reading again after a better crop is
    // the point, and it should not mean starting from the photograph again.
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

/**
 * Throws away a scan this form made and then replaced. Trash first, then purge:
 * the file existed for less than a minute and was never anybody's.
 */
async function discard(fileId) {
  attachmentIds.value = attachmentIds.value.filter((id) => id !== fileId);

  try {
    await api.delete(`/files/${fileId}`);
    await api.delete(`/files/${fileId}/purge`);
  } catch {
    // Worst case it sits in the trash, which is where it belongs anyway.
  }
}

/** Back to the crop, to try again with different edges. */
function readAgain() {
  scanError.value = "";
  scanStage.value = scanPages.value.length ? "trim" : "choosing";
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

/** Set once the record is saved, so its scan is left alone on the way out. */
let saved = false;

onBeforeUnmount(() => {
  releaseOriginals();
  if (pdfUrl.value) URL.revokeObjectURL(pdfUrl.value);
  // Walking away from a form abandons the scan it built along with it. The
  // file only ever existed to be attached to the record that is not going to
  // exist.
  if (!saved) built.value.forEach(discard);
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

    if (scanToken) {
      loadHeldScan();
    } else {
      findPreset(match.type);
    }
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

/** The name printed on the document, whatever the template calls that field. */
function nameOnIt() {
  return (form.value.data.full_name || form.value.data.holder || "").trim();
}

function resolvedTitle() {
  const manual = form.value.title.trim();
  if (manual) return manual;

  const key = titleFieldKey.value;
  if (key) {
    const fromField = form.value.data[key]?.trim();
    if (fromField) return fromField;
  }

  // A document names itself for whose it is and what it is — the same name a
  // scan gives it. Making somebody type "Aisha's health card" underneath a box
  // where they have already typed Aisha is the sort of thing that makes a
  // register feel like paperwork.
  const name = nameOnIt();
  if (name) return `${name} — ${template.value.label}`;

  return template.value?.title_hint ?? template.value?.label ?? "Untitled";
}

function canSave() {
  if (titleFieldKey.value) return Boolean(form.value.data[titleFieldKey.value]?.trim());

  return Boolean(form.value.title.trim() || nameOnIt());
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
      held_by_id: heldById.value,
    };

    if (hasSecrets) {
      payload.secrets = Object.fromEntries(
        secretFields.value
          .filter((f) => form.value.secrets[f.key]?.trim())
          .map((f) => [f.key, form.value.secrets[f.key].trim()]),
      );
    }

    const { data } = await api.post("/records", payload);
    saved = true;
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
            <h1 class="mt-1 text-h2 font-bold text-gray-800">
              {{ scanStage === "choosing" ? "Read a document" : "Straighten the scan" }}
            </h1>
            <p v-if="scanStage !== 'choosing'" class="mt-1 text-body-sm text-gray-500">
              Drag the corners onto the edges of the document, then read it. Nothing is filled in
              until you do.
            </p>
          </div>

          <div class="flex shrink-0 items-center gap-3">
            <button
              v-if="fromScan"
              type="button"
              class="text-body-sm font-medium text-gray-600 hover:text-gray-800"
              @click="scanStage = 'done'"
            >
              Back to the form
            </button>
            <RouterLink
              v-else
              :to="{ name: sectionFor(template.group).route }"
              class="text-body-sm font-medium text-gray-600 hover:text-gray-800"
            >
              Cancel
            </RouterLink>
            <button
              v-if="scanStage !== 'choosing'"
              type="button"
              :disabled="scanStage !== 'trim'"
              class="rounded-base bg-primary-600 px-4 py-2 text-body-sm font-medium text-white transition hover:bg-primary-700 disabled:opacity-50"
              @click="trimAndRead"
            >
              <span v-if="scanStage === 'reading'">
                <i class="fas fa-circle-notch fa-spin mr-1.5" aria-hidden="true"></i>Reading…
              </span>
              <span v-else-if="readsOriginal">Read it</span>
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

        <DocumentSourcePicker
          v-if="scanStage === 'choosing'"
          class="mt-6"
          @select="useFile"
          @cancel="scanStage = fromScan ? 'done' : 'none'"
        />

        <p v-else-if="scanStage === 'loading'" class="mt-8 text-center text-body text-gray-500">
          <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>
          {{ sourceFile ? "Opening the document…" : "Fetching what your phone sent…" }}
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
                autofocus
                :placeholder="resolvedTitle()"
                class="mt-1 w-full border-b-2 border-gray-200 bg-transparent pb-1 text-h2 font-bold text-gray-800 outline-none transition placeholder:font-normal placeholder:text-gray-300 focus:border-primary-400"
              />
              <p v-if="identityField?.hint" class="mt-1 text-caption text-gray-500">
                {{ identityField.hint }}
              </p>
            </div>
          </div>

          <div class="flex shrink-0 items-center gap-3">
            <RouterLink
              :to="{ name: sectionFor(template.group).route }"
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

        <!-- Rather than typing a licence out, point at the one already filed. -->
        <button
          v-if="readablePreset && !fromScan"
          type="button"
          class="mt-4 flex w-full items-center gap-3 rounded-base border border-dashed border-gray-300 px-4 py-3 text-left transition hover:border-primary-400 hover:bg-primary-50"
          @click="scanStage = 'choosing'"
        >
          <i class="fas fa-wand-magic-sparkles text-primary-600" aria-hidden="true"></i>
          <span class="min-w-0 flex-1">
            <span class="block text-body-sm font-medium text-gray-800">
              Fill this in from a scan
            </span>
            <span class="block text-caption text-gray-500">
              Pick a photograph or PDF you've already uploaded — {{ readablePreset.hint }}
            </span>
          </span>
          <i class="fas fa-chevron-right text-gray-300" aria-hidden="true"></i>
        </button>

        <!-- It read the page and got nothing off it. Saying so beats an empty
             form that looks like it simply did not run. -->
        <div
          v-if="readNothing"
          class="mt-4 flex flex-wrap items-center gap-x-3 gap-y-1 rounded-base border border-warning-100 bg-warning-50 px-4 py-3 text-body-sm text-warning-600"
        >
          <span>
            <i class="fas fa-circle-info mr-1.5" aria-hidden="true"></i>
            The scan is attached, but nothing could be read off it.
          </span>
          <span class="text-caption text-gray-600">
            Cropping tight to the document usually fixes it — small print on a big page reads as
            noise.
          </span>
          <button
            type="button"
            class="text-caption font-medium text-warning-600 underline"
            @click="readAgain"
          >
            Crop it and try again
          </button>
        </div>

        <!-- Read off a scan. Nothing is saved until it has been looked at. -->
        <div
          v-if="fromScan && !readNothing"
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
          <button
            type="button"
            class="text-caption font-medium text-primary-700 underline hover:text-primary-800"
            @click="readAgain"
          >
            Adjust and read again
          </button>
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

            <!-- A person is not held by anybody; everything else might be. -->
            <RecordHolderPicker v-if="template.type !== 'person'" v-model="heldById" />

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
