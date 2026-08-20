<script setup>
import { nextTick, onBeforeUnmount, onMounted, ref } from "vue";
import api from "@/api/client";

/**
 * Choose a saved signature, or draw a new one.
 *
 * Small enough to stay a dialog: it is one decision inside the editor, not the
 * task itself.
 */
defineProps({
  signatures: { type: Array, default: () => [] },
});
const emit = defineEmits(["picked", "saved", "close"]);

const mode = ref("saved"); // saved | draw | type
const typed = ref("");
const saving = ref(false);
const error = ref("");
const hasDrawing = ref(false);

const canvas = ref(null);
let context = null;
let drawing = false;
let lastPoint = null;

// Cursive-ish stack so a typed signature does not look like a form field.
const TYPED_FONT = '"Segoe Script", "Brush Script MT", cursive';

async function useDrawing() {
  mode.value = "draw";
  await nextTick();
  setupCanvas();
}

function setupCanvas() {
  const el = canvas.value;
  if (!el) return;

  // Back the canvas at device resolution or the stroke looks furry.
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

function begin(event) {
  event.preventDefault();
  drawing = true;
  lastPoint = pointFrom(event);
}

function stroke(event) {
  if (!drawing) return;
  event.preventDefault();

  const point = pointFrom(event);
  context.beginPath();
  context.moveTo(lastPoint.x, lastPoint.y);
  context.lineTo(point.x, point.y);
  context.stroke();
  lastPoint = point;
  hasDrawing.value = true;
}

function end() {
  drawing = false;
}

function clear() {
  context.clearRect(0, 0, canvas.value.width, canvas.value.height);
  hasDrawing.value = false;
}

/** Renders the typed name to a transparent PNG so it stamps like a drawing. */
function typedToDataUrl() {
  const scratch = document.createElement("canvas");
  scratch.width = 600;
  scratch.height = 200;

  const ctx = scratch.getContext("2d");
  ctx.fillStyle = "#111827";
  ctx.font = `72px ${TYPED_FONT}`;
  ctx.textBaseline = "middle";
  ctx.textAlign = "center";
  ctx.fillText(typed.value.trim(), scratch.width / 2, scratch.height / 2);

  return scratch.toDataURL("image/png");
}

async function saveAndUse() {
  saving.value = true;
  error.value = "";

  try {
    const imageData = mode.value === "draw" ? canvas.value.toDataURL("image/png") : typedToDataUrl();
    const { data } = await api.post("/signatures", { image_data: imageData });

    emit("saved", data.signature);
    emit("picked", String(data.signature.id));
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    saving.value = false;
  }
}

function onKeydown(event) {
  if (event.key === "Escape") emit("close");
}

onMounted(() => document.addEventListener("keydown", onKeydown));
onBeforeUnmount(() => document.removeEventListener("keydown", onKeydown));
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-gray-900/50 p-4"
    @click.self="emit('close')"
  >
    <div
      class="w-full max-w-lg rounded-xl bg-white shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-labelledby="picker-title"
    >
      <header class="flex items-center justify-between border-b border-gray-200 p-5">
        <h2 id="picker-title" class="text-h3 font-semibold text-gray-800">Your signature</h2>
        <button
          type="button"
          class="rounded-md p-2 text-gray-400 hover:bg-gray-100"
          aria-label="Close"
          @click="emit('close')"
        >
          <i class="fas fa-xmark" aria-hidden="true"></i>
        </button>
      </header>

      <div class="p-5">
        <p v-if="error" role="alert" class="mb-3 rounded-base bg-error-50 px-3 py-2 text-body-sm text-error-600">
          {{ error }}
        </p>

        <div class="mb-4 flex gap-2">
          <button
            v-for="option in [
              { value: 'saved', label: 'Saved' },
              { value: 'draw', label: 'Draw' },
              { value: 'type', label: 'Type' },
            ]"
            :key="option.value"
            type="button"
            :aria-pressed="mode === option.value"
            :class="[
              'flex-1 rounded-base border px-3 py-2 text-body-sm font-medium transition',
              mode === option.value
                ? 'border-primary-600 bg-primary-50 text-primary-700'
                : 'border-gray-300 text-gray-600 hover:bg-gray-50',
            ]"
            @click="option.value === 'draw' ? useDrawing() : (mode = option.value)"
          >
            {{ option.label }}
          </button>
        </div>

        <!-- Saved -->
        <template v-if="mode === 'saved'">
          <ul v-if="signatures.length" class="space-y-2">
            <li v-for="signature in signatures" :key="signature.id">
              <button
                type="button"
                class="flex w-full items-center gap-4 rounded-base border border-gray-200 p-3 transition hover:border-primary-400 hover:bg-primary-50"
                @click="emit('picked', String(signature.id))"
              >
                <img :src="signature.image_url" :alt="signature.name" class="h-12 object-contain" />
                <span class="text-body-sm text-gray-600">{{ signature.name }}</span>
              </button>
            </li>
          </ul>

          <p v-else class="py-6 text-center text-body text-gray-500">
            Nothing saved yet — draw or type one.
          </p>
        </template>

        <!-- Draw -->
        <template v-else-if="mode === 'draw'">
          <canvas
            ref="canvas"
            class="h-44 w-full touch-none rounded-lg border-2 border-dashed border-gray-300 bg-white"
            @mousedown="begin"
            @mousemove="stroke"
            @mouseup="end"
            @mouseleave="end"
            @touchstart="begin"
            @touchmove="stroke"
            @touchend="end"
          ></canvas>

          <button type="button" class="mt-2 text-body-sm text-gray-500 hover:underline" @click="clear">
            Clear
          </button>
        </template>

        <!-- Type -->
        <template v-else>
          <label for="typed-signature" class="mb-2 block text-body-sm text-gray-600">
            Your name
          </label>
          <input
            id="typed-signature"
            v-model="typed"
            type="text"
            class="w-full rounded-base border border-gray-300 px-3 py-2 outline-none focus:ring-2 focus:ring-primary-500"
          />

          <p
            v-if="typed.trim()"
            class="mt-4 rounded-lg border border-gray-200 py-6 text-center text-3xl text-gray-900"
            :style="{ fontFamily: TYPED_FONT }"
          >
            {{ typed }}
          </p>
        </template>
      </div>

      <footer v-if="mode !== 'saved'" class="flex justify-end gap-3 border-t border-gray-200 p-5">
        <button
          type="button"
          class="rounded-base border border-gray-300 px-4 py-2 text-body-sm font-medium text-gray-700"
          @click="emit('close')"
        >
          Cancel
        </button>
        <button
          type="button"
          :disabled="saving || (mode === 'draw' ? !hasDrawing : !typed.trim())"
          class="rounded-base gradient-main px-5 py-2 text-body-sm font-semibold text-white disabled:opacity-50"
          @click="saveAndUse"
        >
          {{ saving ? "Saving…" : "Use signature" }}
        </button>
      </footer>
    </div>
  </div>
</template>
