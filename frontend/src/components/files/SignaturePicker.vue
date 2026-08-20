<script setup>
import { nextTick, onBeforeUnmount, onMounted, ref } from "vue";
import api from "@/api/client";
import { useDialog } from "@/composables/useDialog";

/**
 * Choose a saved signature, or draw a new one.
 *
 * Small enough to stay a dialog: it is one decision inside the editor, not the
 * task itself.
 */
defineProps({
  signatures: { type: Array, default: () => [] },
});
const emit = defineEmits(["picked", "saved", "changed", "close"]);

const dialog = useDialog();

const mode = ref("saved"); // saved | draw | type | phone
const managing = ref(false);
const phoneSession = ref(null);
let poller = null;
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

/* ------------------------------------------------------------- on a phone */

async function startPhoneCapture() {
  mode.value = "phone";
  phoneSession.value = null;
  error.value = "";

  try {
    const { data } = await api.post("/signatures/session");
    phoneSession.value = data;
    pollForPhone(data.url.split("/signature/").pop());
  } catch (e) {
    error.value = e.userMessage;
  }
}

// The phone cannot reach the desktop, so the desktop asks.
function pollForPhone(token) {
  stopPolling();

  poller = setInterval(async () => {
    try {
      const { data } = await api.get(`/signatures/session/${token}/status`);
      if (!data.receipt) return;

      stopPolling();
      const { data: list } = await api.get("/signatures");
      const drawn = list.signatures.find((s) => s.id === data.receipt.signature_id);

      emit("changed", list.signatures);
      if (drawn) {
        emit("saved", drawn);
        emit("picked", String(drawn.id));
      }
    } catch {
      // Try again on the next tick.
    }
  }, 2500);
}

function stopPolling() {
  if (poller) clearInterval(poller);
  poller = null;
}

/* -------------------------------------------------------------- managing */

async function makeDefault(signature) {
  await api.patch(`/signatures/${signature.id}`, { is_default: true });
  const { data } = await api.get("/signatures");
  emit("changed", data.signatures);
}

async function remove(signature) {
  const ok = await dialog.confirm({
    title: `Delete "${signature.name}"?`,
    message: "Documents you have already signed keep their signature.",
    confirmLabel: "Delete",
    danger: true,
  });
  if (!ok) return;

  await api.delete(`/signatures/${signature.id}`);
  const { data } = await api.get("/signatures");
  emit("changed", data.signatures);
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
onBeforeUnmount(() => {
  stopPolling();
  document.removeEventListener("keydown", onKeydown);
});
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
              { value: 'phone', label: 'On phone' },
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
            @click="
              option.value === 'draw'
                ? useDrawing()
                : option.value === 'phone'
                  ? startPhoneCapture()
                  : (mode = option.value)
            "
          >
            {{ option.label }}
          </button>
        </div>

        <!-- Saved -->
        <template v-if="mode === 'saved'">
          <div v-if="signatures.length" class="mb-2 flex justify-end">
            <button
              type="button"
              class="text-body-sm font-medium text-primary-600 hover:underline"
              @click="managing = !managing"
            >
              {{ managing ? "Done" : "Manage" }}
            </button>
          </div>

          <ul v-if="signatures.length" class="space-y-2">
            <li
              v-for="signature in signatures"
              :key="signature.id"
              class="flex items-center gap-3 rounded-base border border-gray-200 p-3"
            >
              <button
                type="button"
                class="flex min-w-0 flex-1 items-center gap-4 text-left"
                :disabled="managing"
                @click="emit('picked', String(signature.id))"
              >
                <img :src="signature.image_url" :alt="signature.name" class="h-12 object-contain" />
                <span class="min-w-0">
                  <span class="block truncate text-body-sm text-gray-700">{{ signature.name }}</span>
                  <span v-if="signature.is_default" class="text-caption text-primary-600">Default</span>
                </span>
              </button>

              <template v-if="managing">
                <button
                  v-if="!signature.is_default"
                  type="button"
                  class="shrink-0 rounded-base border border-gray-300 px-2 py-1 text-caption font-medium text-gray-600 hover:bg-gray-50"
                  @click="makeDefault(signature)"
                >
                  Make default
                </button>
                <button
                  type="button"
                  class="shrink-0 rounded-md p-2 text-error-500 hover:bg-error-50"
                  :aria-label="`Delete ${signature.name}`"
                  @click="remove(signature)"
                >
                  <i class="fas fa-trash" aria-hidden="true"></i>
                </button>
              </template>
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

        <!-- On a phone -->
        <template v-else-if="mode === 'phone'">
          <div v-if="phoneSession" class="text-center">
            <div class="mx-auto w-48" v-html="phoneSession.qr_svg"></div>
            <p class="mt-3 text-body-sm text-gray-600">
              Scan this and draw with your finger — easier than a mouse.
            </p>
            <p class="mt-1 flex items-center justify-center gap-2 text-caption text-gray-400">
              <i class="fas fa-circle-notch fa-spin" aria-hidden="true"></i>
              Waiting for your phone…
            </p>
          </div>
          <p v-else class="py-8 text-center text-body text-gray-500">
            <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Creating a link…
          </p>
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

      <footer v-if="mode === 'draw' || mode === 'type'" class="flex justify-end gap-3 border-t border-gray-200 p-5">
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
