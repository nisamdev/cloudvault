<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from "vue";
import api from "@/api/client";
import { useFilesStore } from "@/stores/files";

const props = defineProps({
  file: { type: Object, required: true },
});
const emit = defineEmits(["close", "signed"]);

const filesStore = useFilesStore();

const step = ref("choose"); // choose → place → done
const signatures = ref([]);
const selected = ref(null);
const pages = ref([]);
const loading = ref(true);
const saving = ref(false);
const error = ref("");

// Placement is stored as fractions of the page, so it survives whatever size
// the preview happens to render at.
const placement = ref({ page: 1, x: 0.55, y: 0.7, width: 0.28 });
const dragging = ref(false);

const canvas = ref(null);
const drawing = ref(false);
const hasDrawing = ref(false);
let context = null;
let lastPoint = null;

const currentPage = computed(() => pages.value.find((p) => p.number === placement.value.page));

async function load() {
  loading.value = true;
  try {
    const [sigs, pageData] = await Promise.all([
      api.get("/signatures"),
      api.get(`/files/${props.file.id}/pages`),
    ]);
    signatures.value = sigs.data.signatures;
    pages.value = pageData.data.pages;
    selected.value = signatures.value[0] ?? null;
    if (selected.value) step.value = "place";
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}

/* ---------------------------------------------------------------- drawing */

async function startNewSignature() {
  step.value = "draw";
  await nextTick();

  const el = canvas.value;
  // Backing store at device resolution keeps the stroke crisp; the CSS size
  // stays the same.
  const ratio = window.devicePixelRatio || 1;
  el.width = el.offsetWidth * ratio;
  el.height = el.offsetHeight * ratio;

  context = el.getContext("2d");
  context.scale(ratio, ratio);
  context.lineWidth = 2.5;
  context.lineCap = "round";
  context.lineJoin = "round";
  context.strokeStyle = "#111827";
  hasDrawing.value = false;
}

function pointFrom(event) {
  const rect = canvas.value.getBoundingClientRect();
  const source = event.touches?.[0] ?? event;
  return { x: source.clientX - rect.left, y: source.clientY - rect.top };
}

function beginStroke(event) {
  event.preventDefault();
  drawing.value = true;
  lastPoint = pointFrom(event);
}

function stroke(event) {
  if (!drawing.value) return;
  event.preventDefault();

  const point = pointFrom(event);
  context.beginPath();
  context.moveTo(lastPoint.x, lastPoint.y);
  context.lineTo(point.x, point.y);
  context.stroke();
  lastPoint = point;
  hasDrawing.value = true;
}

function endStroke() {
  drawing.value = false;
}

function clearCanvas() {
  context.clearRect(0, 0, canvas.value.width, canvas.value.height);
  hasDrawing.value = false;
}

async function saveSignature() {
  saving.value = true;
  error.value = "";

  try {
    const { data } = await api.post("/signatures", {
      image_data: canvas.value.toDataURL("image/png"),
    });
    signatures.value.push(data.signature);
    selected.value = data.signature;
    step.value = "place";
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    saving.value = false;
  }
}

/* -------------------------------------------------------------- placement */

function moveTo(event) {
  const rect = event.currentTarget.getBoundingClientRect();
  const source = event.touches?.[0] ?? event;

  placement.value = {
    ...placement.value,
    // Centre the signature on the pointer.
    x: Math.min(Math.max((source.clientX - rect.left) / rect.width - placement.value.width / 2, 0), 1),
    y: Math.min(Math.max((source.clientY - rect.top) / rect.height, 0), 1),
  };
}

function onPageClick(event) {
  moveTo(event);
}

function onPageDrag(event) {
  if (!dragging.value) return;
  event.preventDefault();
  moveTo(event);
}

async function sign() {
  saving.value = true;
  error.value = "";

  try {
    const { data } = await api.post(`/files/${props.file.id}/sign`, {
      signature_id: selected.value.id,
      placements: [placement.value],
    });

    const index = filesStore.items.findIndex((f) => f.id === data.file.id);
    if (index >= 0) filesStore.items.splice(index, 1, data.file);

    step.value = "done";
    emit("signed", data.file);
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    saving.value = false;
  }
}

function onKeydown(event) {
  if (event.key === "Escape") emit("close");
}

onMounted(() => {
  load();
  document.addEventListener("keydown", onKeydown);
});

onBeforeUnmount(() => document.removeEventListener("keydown", onKeydown));
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-gray-900/60 p-4"
    @click.self="emit('close')"
  >
    <div
      class="flex max-h-[92vh] w-full max-w-3xl flex-col rounded-xl bg-white shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-labelledby="sign-title"
    >
      <header class="flex items-start justify-between border-b border-gray-200 p-6">
        <div class="min-w-0">
          <h2 id="sign-title" class="text-h3 font-semibold text-gray-800">Sign document</h2>
          <p class="mt-1 truncate text-body-sm text-gray-500">{{ file.name }}</p>
        </div>
        <button
          type="button"
          class="rounded-md p-2 text-gray-400 hover:bg-gray-100 hover:text-gray-600"
          aria-label="Close"
          @click="emit('close')"
        >
          <i class="fas fa-xmark" aria-hidden="true"></i>
        </button>
      </header>

      <div class="min-h-0 flex-1 overflow-y-auto p-6">
        <p
          v-if="error"
          role="alert"
          class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
        >
          {{ error }}
        </p>

        <p v-if="loading" class="py-10 text-center text-body text-gray-500">
          <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Opening the document…
        </p>

        <!-- No signature saved yet -->
        <div v-else-if="step === 'choose'" class="py-8 text-center">
          <i class="fas fa-signature text-4xl text-gray-300" aria-hidden="true"></i>
          <h3 class="mt-4 text-h3 font-semibold text-gray-800">Create a signature first</h3>
          <p class="mt-2 text-body text-gray-500">Draw it once and reuse it on any document.</p>
          <button
            type="button"
            class="mt-6 rounded-base gradient-main px-6 py-2 font-semibold text-white"
            @click="startNewSignature"
          >
            Draw signature
          </button>
        </div>

        <!-- Drawing -->
        <div v-else-if="step === 'draw'">
          <p class="mb-2 text-body-sm text-gray-600">Draw your signature below.</p>
          <canvas
            ref="canvas"
            class="h-44 w-full touch-none rounded-lg border-2 border-dashed border-gray-300 bg-white"
            @mousedown="beginStroke"
            @mousemove="stroke"
            @mouseup="endStroke"
            @mouseleave="endStroke"
            @touchstart="beginStroke"
            @touchmove="stroke"
            @touchend="endStroke"
          ></canvas>

          <div class="mt-3 flex justify-between">
            <button
              type="button"
              class="rounded-base border border-gray-300 px-4 py-2 text-body-sm font-medium text-gray-700"
              @click="clearCanvas"
            >
              Clear
            </button>
            <button
              type="button"
              :disabled="!hasDrawing || saving"
              class="rounded-base gradient-main px-6 py-2 text-body-sm font-semibold text-white disabled:opacity-50"
              @click="saveSignature"
            >
              {{ saving ? "Saving…" : "Use this signature" }}
            </button>
          </div>
        </div>

        <!-- Placing -->
        <div v-else-if="step === 'place'">
          <div class="mb-4 flex flex-wrap items-center gap-3">
            <label for="sign-signature" class="text-body-sm font-medium text-gray-700">Signature</label>
            <select
              id="sign-signature"
              class="rounded-base border border-gray-300 px-3 py-2 text-body-sm"
              @change="selected = signatures.find((s) => String(s.id) === $event.target.value)"
            >
              <option v-for="s in signatures" :key="s.id" :value="s.id">{{ s.name }}</option>
            </select>

            <button
              type="button"
              class="text-body-sm font-medium text-primary-600 hover:underline"
              @click="startNewSignature"
            >
              Draw a new one
            </button>

            <div v-if="pages.length > 1" class="flex items-center gap-2">
              <label for="sign-page" class="text-body-sm font-medium text-gray-700">Page</label>
              <select
                id="sign-page"
                class="rounded-base border border-gray-300 px-3 py-2 text-body-sm"
                @change="placement = { ...placement, page: Number($event.target.value) }"
              >
                <option v-for="p in pages" :key="p.number" :value="p.number">{{ p.number }}</option>
              </select>
            </div>

            <div class="flex items-center gap-2">
              <label for="sign-size" class="text-body-sm font-medium text-gray-700">Size</label>
              <input
                id="sign-size"
                type="range"
                min="0.1"
                max="0.6"
                step="0.02"
                :value="placement.width"
                @input="placement = { ...placement, width: Number($event.target.value) }"
              />
            </div>
          </div>

          <p class="mb-2 text-caption text-gray-500">
            Click on the page to position your signature, or drag it.
          </p>

          <!-- The page image is the coordinate space; positions are stored as
               fractions so they hold whatever size this renders at. -->
          <div
            class="relative mx-auto w-full max-w-xl cursor-crosshair select-none overflow-hidden rounded-lg border border-gray-300"
            @click="onPageClick"
            @mousedown="dragging = true"
            @mousemove="onPageDrag"
            @mouseup="dragging = false"
            @mouseleave="dragging = false"
          >
            <img v-if="currentPage" :src="currentPage.image" :alt="`Page ${placement.page}`" class="block w-full" />

            <img
              v-if="selected"
              :src="selected.image_url"
              alt="Signature position"
              class="pointer-events-none absolute opacity-90"
              :style="{
                left: `${placement.x * 100}%`,
                top: `${placement.y * 100}%`,
                width: `${placement.width * 100}%`,
              }"
            />
          </div>
        </div>

        <!-- Done -->
        <div v-else class="py-10 text-center">
          <i class="fas fa-circle-check text-4xl text-success-500" aria-hidden="true"></i>
          <h3 class="mt-4 text-h3 font-semibold text-gray-800">Document signed</h3>
          <p class="mt-2 text-body text-gray-500">
            The unsigned original is kept as an earlier version.
          </p>
        </div>
      </div>

      <footer v-if="step === 'place' || step === 'done'" class="flex justify-end gap-3 border-t border-gray-200 p-6">
        <button
          type="button"
          class="rounded-base border border-gray-300 px-4 py-2 text-body-sm font-medium text-gray-700 hover:bg-gray-50"
          @click="emit('close')"
        >
          {{ step === "done" ? "Close" : "Cancel" }}
        </button>
        <button
          v-if="step === 'place'"
          type="button"
          :disabled="saving || !selected"
          class="rounded-base gradient-main px-6 py-2 text-body-sm font-semibold text-white disabled:opacity-60"
          @click="sign"
        >
          {{ saving ? "Signing…" : "Sign document" }}
        </button>
      </footer>
    </div>
  </div>
</template>
