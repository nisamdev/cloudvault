<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import api from "@/api/client";
import SignaturePicker from "@/components/files/SignaturePicker.vue";

/**
 * Full-page document editor, modelled on the LocalSign editor rather than a
 * dialog: signing a document is a task you sit inside, not a confirmation.
 *
 * Pages are PNGs rendered by the server (libvips/poppler), so no PDF library
 * runs in the browser. Field geometry is stored as fractions of the page, which
 * survives zooming and any render width — the pixel coordinates LocalSign used
 * only hold if the preview is rendered at exactly 72dpi.
 */
const route = useRoute();
const router = useRouter();

const file = ref(null);
const pages = ref([]);
const fields = ref([]);
const signatures = ref([]);
const loading = ref(true);
const saving = ref(false);
const error = ref("");
const done = ref(false);

const tool = ref("select");
const selectedId = ref(null);
const zoom = ref(1);
const pickerFor = ref(null);

const pageRefs = ref({});
let nextId = 1;

const TOOLS = [
  { value: "select", label: "Select", icon: "fa-arrow-pointer", section: null },
  { value: "text", label: "Text", icon: "fa-font", section: "Fill" },
  { value: "date", label: "Date", icon: "fa-calendar-day", section: null },
  { value: "checkbox", label: "Check", icon: "fa-square-check", section: null },
  { value: "signature", label: "Signature", icon: "fa-signature", section: "Sign" },
  { value: "initials", label: "Initials", icon: "fa-pen-nib", section: null },
];

// Sensible starting size per type, as a fraction of the page.
const DEFAULT_SIZE = {
  text: { width: 0.34, height: 0.035 },
  date: { width: 0.22, height: 0.028 },
  checkbox: { width: 0.028, height: 0.02 },
  signature: { width: 0.26, height: 0.07 },
  initials: { width: 0.1, height: 0.05 },
};

const selected = computed(() => fields.value.find((f) => f.id === selectedId.value) ?? null);
const canSave = computed(() => fields.value.some((f) => hasValue(f)));

function hasValue(field) {
  if (field.type === "checkbox") return field.value === true;
  return String(field.value ?? "").trim().length > 0;
}

function fieldsOn(pageNumber) {
  return fields.value.filter((f) => f.page === pageNumber);
}

function signatureFor(field) {
  if (String(field.value ?? "").startsWith("data:image")) return field.value;
  return signatures.value.find((s) => String(s.id) === String(field.value))?.image_url ?? null;
}

async function load() {
  try {
    const [detail, pageData, sigs] = await Promise.all([
      api.get(`/files/${route.params.id}`),
      api.get(`/files/${route.params.id}/pages`),
      api.get("/signatures"),
    ]);
    file.value = detail.data.file;
    pages.value = pageData.data.pages;
    signatures.value = sigs.data.signatures;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}

/* --------------------------------------------------------------- placing */

function onPageClick(event, pageNumber) {
  if (tool.value === "select") {
    selectedId.value = null;
    return;
  }

  const rect = event.currentTarget.getBoundingClientRect();
  const size = DEFAULT_SIZE[tool.value];

  const field = {
    id: nextId++,
    type: tool.value,
    page: pageNumber,
    // Dropped centred on the click, like LocalSign does.
    x: clamp((event.clientX - rect.left) / rect.width - size.width / 2),
    y: clamp((event.clientY - rect.top) / rect.height - size.height / 2),
    ...size,
    value: tool.value === "checkbox" ? true : "",
    font_size: 12,
    bold: false,
    italic: false,
    align: "left",
    color: "#111827",
  };

  fields.value.push(field);
  selectedId.value = field.id;
  tool.value = "select";

  if (field.type === "signature" || field.type === "initials") {
    pickerFor.value = field.id;
  } else if (field.type === "date") {
    field.value = new Date().toLocaleDateString(undefined, { day: "numeric", month: "long", year: "numeric" });
  } else if (field.type === "text") {
    nextTick(() => document.getElementById(`field-input-${field.id}`)?.focus());
  }
}

function clamp(value) {
  return Math.min(Math.max(value, 0), 1);
}

/* ------------------------------------------------------- drag and resize */

function startDrag(event, field) {
  if (event.button !== 0) return;
  event.preventDefault();
  event.stopPropagation();
  selectedId.value = field.id;

  const page = pageRefs.value[field.page];
  const rect = page.getBoundingClientRect();
  const offsetX = (event.clientX - rect.left) / rect.width - field.x;
  const offsetY = (event.clientY - rect.top) / rect.height - field.y;

  const move = (e) => {
    field.x = clamp((e.clientX - rect.left) / rect.width - offsetX);
    field.y = clamp((e.clientY - rect.top) / rect.height - offsetY);
  };
  const up = () => {
    document.removeEventListener("mousemove", move);
    document.removeEventListener("mouseup", up);
  };

  document.addEventListener("mousemove", move);
  document.addEventListener("mouseup", up);
}

function startResize(event, field) {
  event.preventDefault();
  event.stopPropagation();

  const page = pageRefs.value[field.page];
  const rect = page.getBoundingClientRect();

  const move = (e) => {
    field.width = Math.max((e.clientX - rect.left) / rect.width - field.x, 0.02);
    field.height = Math.max((e.clientY - rect.top) / rect.height - field.y, 0.012);
  };
  const up = () => {
    document.removeEventListener("mousemove", move);
    document.removeEventListener("mouseup", up);
  };

  document.addEventListener("mousemove", move);
  document.addEventListener("mouseup", up);
}

/* ---------------------------------------------------------------- fields */

function removeSelected() {
  if (!selectedId.value) return;
  fields.value = fields.value.filter((f) => f.id !== selectedId.value);
  selectedId.value = null;
}

function duplicateSelected() {
  const original = selected.value;
  if (!original) return;

  const copy = { ...original, id: nextId++, y: clamp(original.y + original.height + 0.01) };
  fields.value.push(copy);
  selectedId.value = copy.id;
}

function onSignaturePicked(value) {
  const field = fields.value.find((f) => f.id === pickerFor.value);
  if (field) field.value = value;
  pickerFor.value = null;
}

function onSignatureSaved(signature) {
  signatures.value.push(signature);
}

/* ------------------------------------------------------------------ save */

async function save() {
  saving.value = true;
  error.value = "";

  try {
    const { data } = await api.post(`/files/${route.params.id}/sign`, {
      fields: fields.value.filter(hasValue).map((f) => ({
        type: f.type,
        page: f.page,
        x: f.x,
        y: f.y,
        width: f.width,
        height: f.height,
        value: f.value,
        font_size: f.font_size,
        bold: f.bold,
        italic: f.italic,
        align: f.align,
        color: f.color,
      })),
    });

    file.value = data.file;
    done.value = true;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    saving.value = false;
  }
}

function onKeydown(event) {
  if (event.target.matches("input, textarea")) return;

  if (event.key === "Escape") {
    tool.value = "select";
    selectedId.value = null;
  } else if ((event.key === "Delete" || event.key === "Backspace") && selectedId.value) {
    event.preventDefault();
    removeSelected();
  } else if (event.key === "t") {
    tool.value = "text";
  } else if (event.key === "s") {
    tool.value = "signature";
  }
}

onMounted(() => {
  load();
  document.addEventListener("keydown", onKeydown);
});

onBeforeUnmount(() => document.removeEventListener("keydown", onKeydown));
</script>

<template>
  <div class="flex h-screen flex-col bg-gray-100">
    <!-- Top bar -->
    <header class="flex h-14 shrink-0 items-center gap-4 border-b border-gray-200 bg-white px-4">
      <button
        type="button"
        class="flex items-center gap-2 text-body-sm text-gray-600 hover:text-primary-600"
        @click="router.push({ name: 'dashboard' })"
      >
        <i class="fas fa-arrow-left" aria-hidden="true"></i>
        Back to files
      </button>

      <span class="h-5 w-px bg-gray-200"></span>

      <h1 class="min-w-0 flex-1 truncate text-body font-semibold text-gray-800">
        {{ file?.name ?? "Loading…" }}
      </h1>

      <div v-if="pages.length" class="flex items-center gap-2 text-body-sm text-gray-500">
        <label for="zoom" class="sr-only">Zoom</label>
        <select
          id="zoom"
          v-model.number="zoom"
          class="rounded-base border border-gray-300 px-2 py-1 text-body-sm"
        >
          <option :value="0.75">75%</option>
          <option :value="1">100%</option>
          <option :value="1.25">125%</option>
          <option :value="1.5">150%</option>
        </select>
        <span>{{ pages.length }} page{{ pages.length === 1 ? "" : "s" }}</span>
      </div>

      <button
        type="button"
        :disabled="!canSave || saving"
        class="rounded-base gradient-main px-5 py-2 text-body-sm font-semibold text-white transition hover:opacity-95 disabled:cursor-not-allowed disabled:opacity-50"
        @click="save"
      >
        {{ saving ? "Applying…" : "Apply and save" }}
      </button>
    </header>

    <div class="flex min-h-0 flex-1">
      <!-- Tool palette -->
      <aside class="flex w-24 shrink-0 flex-col items-center gap-1 border-r border-gray-200 bg-white py-3">
        <template v-for="item in TOOLS" :key="item.value">
          <p
            v-if="item.section"
            class="w-full pt-3 text-center text-caption font-bold uppercase tracking-wider text-gray-400"
          >
            {{ item.section }}
          </p>

          <button
            type="button"
            :aria-pressed="tool === item.value"
            :class="[
              'flex w-20 flex-col items-center gap-1 rounded-base px-2 py-2 transition',
              tool === item.value ? 'bg-primary-50 text-primary-700' : 'text-gray-500 hover:bg-gray-100',
            ]"
            @click="tool = item.value"
          >
            <i :class="['fas', item.icon, 'text-lg']" aria-hidden="true"></i>
            <span class="text-caption font-semibold">{{ item.label }}</span>
          </button>
        </template>

        <div class="my-2 h-px w-14 bg-gray-200"></div>

        <button
          type="button"
          :disabled="!selected"
          class="flex w-20 flex-col items-center gap-1 rounded-base px-2 py-2 text-gray-500 transition hover:bg-gray-100 disabled:opacity-40"
          @click="duplicateSelected"
        >
          <i class="fas fa-clone text-lg" aria-hidden="true"></i>
          <span class="text-caption font-semibold">Duplicate</span>
        </button>

        <button
          type="button"
          :disabled="!selected"
          class="flex w-20 flex-col items-center gap-1 rounded-base px-2 py-2 text-error-600 transition hover:bg-error-50 disabled:opacity-40"
          @click="removeSelected"
        >
          <i class="fas fa-trash text-lg" aria-hidden="true"></i>
          <span class="text-caption font-semibold">Delete</span>
        </button>
      </aside>

      <!-- Pages -->
      <main class="flex-1 overflow-auto p-6">
        <p v-if="loading" class="text-center text-body text-gray-500">
          <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Opening document…
        </p>

        <p
          v-else-if="error && !pages.length"
          role="alert"
          class="mx-auto max-w-lg rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
        >
          {{ error }}
        </p>

        <div v-else class="flex flex-col items-center gap-6">
          <p
            v-if="error"
            role="alert"
            class="w-full max-w-2xl rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
          >
            {{ error }}
          </p>

          <p v-if="tool !== 'select'" class="text-body-sm text-primary-700">
            Click on the page to place the {{ tool }}.
          </p>

          <div v-for="page in pages" :key="page.number" class="w-full" :style="{ maxWidth: `${900 * zoom}px` }">
            <p class="mb-1 text-caption text-gray-500">Page {{ page.number }}</p>

            <div
              :ref="(el) => (pageRefs[page.number] = el)"
              class="relative select-none bg-white shadow-lg"
              :class="tool === 'select' ? 'cursor-default' : 'cursor-crosshair'"
              @click="onPageClick($event, page.number)"
            >
              <img :src="page.image" :alt="`Page ${page.number}`" class="block w-full" draggable="false" />

              <!-- Field overlays -->
              <div
                v-for="field in fieldsOn(page.number)"
                :key="field.id"
                :class="[
                  'absolute flex items-center rounded border-2',
                  selectedId === field.id
                    ? 'border-info-500 bg-info-500/10'
                    : 'border-primary-600 bg-primary-600/5',
                ]"
                :style="{
                  left: `${field.x * 100}%`,
                  top: `${field.y * 100}%`,
                  width: `${field.width * 100}%`,
                  height: `${field.height * 100}%`,
                }"
                @mousedown="startDrag($event, field)"
                @click.stop="selectedId = field.id"
              >
                <input
                  v-if="field.type === 'text' || field.type === 'date'"
                  :id="`field-input-${field.id}`"
                  v-model="field.value"
                  type="text"
                  class="h-full w-full border-none bg-transparent px-1 outline-none"
                  :style="{
                    fontSize: `${field.font_size * zoom * 0.9}px`,
                    fontWeight: field.bold ? '700' : '400',
                    fontStyle: field.italic ? 'italic' : 'normal',
                    textAlign: field.align,
                    color: field.color,
                  }"
                  :placeholder="field.type === 'date' ? 'Date' : 'Type here…'"
                  @mousedown.stop
                />

                <span
                  v-else-if="field.type === 'checkbox'"
                  class="flex h-full w-full items-center justify-center text-primary-600"
                >
                  <i class="fas fa-check" aria-hidden="true"></i>
                </span>

                <img
                  v-else-if="signatureFor(field)"
                  :src="signatureFor(field)"
                  alt=""
                  class="pointer-events-none h-full w-full object-contain"
                />

                <button
                  v-else
                  type="button"
                  class="h-full w-full text-caption text-primary-700"
                  @click.stop="pickerFor = field.id"
                >
                  Choose {{ field.type }}
                </button>

                <!-- Resize handle -->
                <span
                  v-if="selectedId === field.id"
                  class="absolute -bottom-1.5 -right-1.5 h-3 w-3 cursor-se-resize rounded-full border border-white bg-info-500"
                  @mousedown.stop="startResize($event, field)"
                ></span>
              </div>
            </div>
          </div>
        </div>
      </main>

      <!--
        Always present, never conditional: rendering this only when a field is
        selected shrinks the page area mid-interaction, so the document jumps
        the moment you place something. Reserving the width keeps the page
        still.
      -->
      <aside class="w-64 shrink-0 border-l border-gray-200 bg-white p-4">
        <p v-if="!selected" class="text-body-sm text-gray-400">
          Select a field to change its size, style or signature.
        </p>

        <template v-else>
        <h2 class="mb-3 text-label font-medium uppercase tracking-wide text-gray-500">
          {{ selected.type }}
        </h2>

        <template v-if="selected.type === 'text' || selected.type === 'date'">
          <label for="prop-size" class="mb-1 block text-body-sm text-gray-600">Text size</label>
          <input
            id="prop-size"
            v-model.number="selected.font_size"
            type="range"
            min="7"
            max="36"
            class="w-full"
          />

          <div class="mt-3 flex gap-2">
            <button
              type="button"
              :aria-pressed="selected.bold"
              :class="['rounded-base border px-3 py-1 font-bold', selected.bold ? 'border-primary-600 bg-primary-50 text-primary-700' : 'border-gray-300 text-gray-600']"
              @click="selected.bold = !selected.bold"
            >
              B
            </button>
            <button
              type="button"
              :aria-pressed="selected.italic"
              :class="['rounded-base border px-3 py-1 italic', selected.italic ? 'border-primary-600 bg-primary-50 text-primary-700' : 'border-gray-300 text-gray-600']"
              @click="selected.italic = !selected.italic"
            >
              I
            </button>
          </div>

          <label for="prop-align" class="mb-1 mt-3 block text-body-sm text-gray-600">Align</label>
          <select
            id="prop-align"
            v-model="selected.align"
            class="w-full rounded-base border border-gray-300 px-2 py-1 text-body-sm"
          >
            <option value="left">Left</option>
            <option value="center">Centre</option>
            <option value="right">Right</option>
          </select>
        </template>

        <template v-else-if="selected.type === 'signature' || selected.type === 'initials'">
          <button
            type="button"
            class="w-full rounded-base border border-gray-300 py-2 text-body-sm font-medium text-gray-700 hover:bg-gray-50"
            @click="pickerFor = selected.id"
          >
            Change signature
          </button>
        </template>

        <p class="mt-4 text-caption text-gray-400">
          Drag to move, pull the corner to resize, Delete to remove.
        </p>
        </template>
      </aside>
    </div>

    <!-- Saved -->
    <div v-if="done" class="fixed inset-0 z-50 flex items-center justify-center bg-gray-900/60 p-4">
      <div class="w-full max-w-sm rounded-xl bg-white p-8 text-center shadow-2xl">
        <i class="fas fa-circle-check text-4xl text-success-500" aria-hidden="true"></i>
        <h2 class="mt-4 text-h3 font-semibold text-gray-800">Document saved</h2>
        <p class="mt-2 text-body text-gray-500">
          The original is kept as an earlier version.
        </p>
        <div class="mt-6 flex gap-3">
          <button
            type="button"
            class="flex-1 rounded-base border border-gray-300 py-2 font-medium text-gray-700"
            @click="done = false"
          >
            Keep editing
          </button>
          <button
            type="button"
            class="flex-1 rounded-base gradient-main py-2 font-semibold text-white"
            @click="router.push({ name: 'dashboard' })"
          >
            Done
          </button>
        </div>
      </div>
    </div>

    <SignaturePicker
      v-if="pickerFor"
      :signatures="signatures"
      @picked="onSignaturePicked"
      @saved="onSignatureSaved"
      @close="pickerFor = null"
    />
  </div>
</template>
