<script setup>
import { nextTick, onMounted, ref } from "vue";
import { useRoute } from "vue-router";
import api from "@/api/client";

/**
 * Draw a signature on a phone and send it back to the desktop.
 *
 * Same shape as the scan page: the token in the URL is the credential, the
 * phone never signs in, and a finger beats a mouse for this particular job.
 */
const route = useRoute();

const session = ref(null);
const loading = ref(true);
const saving = ref(false);
const error = ref("");
const done = ref(false);
const hasDrawing = ref(false);

const canvas = ref(null);
let context = null;
let drawing = false;
let lastPoint = null;

async function load() {
  try {
    const { data } = await api.get(`/signatures/session/${route.params.token}`);
    session.value = data;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }

  // Only now is the canvas in the DOM: it renders behind `v-else`, so setting
  // it up before `loading` flips leaves the 2D context null and every stroke
  // throws.
  await nextTick();
  setupCanvas();
}

function setupCanvas() {
  const el = canvas.value;
  if (!el) return;

  const ratio = window.devicePixelRatio || 1;
  el.width = el.offsetWidth * ratio;
  el.height = el.offsetHeight * ratio;

  context = el.getContext("2d");
  context.scale(ratio, ratio);
  // Heavier than on desktop: a fingertip is a blunt instrument.
  context.lineWidth = 3.5;
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

async function save() {
  saving.value = true;
  error.value = "";

  try {
    await api.post(`/signatures/session/${route.params.token}`, {
      image_data: canvas.value.toDataURL("image/png"),
    });
    done.value = true;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    saving.value = false;
  }
}

onMounted(load);
</script>

<template>
  <div class="min-h-screen bg-gray-50">
    <header class="gradient-main px-4 py-5 text-white">
      <div class="mx-auto flex max-w-lg items-center gap-3">
        <i class="fas fa-signature text-xl" aria-hidden="true"></i>
        <div class="min-w-0">
          <h1 class="text-h4 font-bold">Draw your signature</h1>
          <p v-if="session" class="truncate text-caption text-white/80">{{ session.account }}</p>
        </div>
      </div>
    </header>

    <main class="mx-auto max-w-lg px-4 py-6">
      <p v-if="loading" class="text-center text-body text-gray-500">
        <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Checking the link…
      </p>

      <div v-else-if="done" class="rounded-xl bg-white p-8 text-center shadow-sm">
        <i class="fas fa-circle-check text-4xl text-success-500" aria-hidden="true"></i>
        <h2 class="mt-4 text-h3 font-semibold text-gray-800">Sent to CloudVault</h2>
        <p class="mt-2 text-body text-gray-500">It has appeared on your computer. You can close this.</p>
      </div>

      <div v-else-if="!session" class="rounded-xl bg-white p-8 text-center shadow-sm">
        <i class="fas fa-link-slash text-4xl text-gray-300" aria-hidden="true"></i>
        <h2 class="mt-4 text-h3 font-semibold text-gray-800">This link has expired</h2>
        <p class="mt-2 text-body text-gray-500">{{ error || "Create a new one from CloudVault." }}</p>
      </div>

      <template v-else>
        <p v-if="error" role="alert" class="mb-3 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
          {{ error }}
        </p>

        <p class="mb-3 text-body text-gray-600">Sign inside the box with your finger.</p>

        <canvas
          ref="canvas"
          class="h-64 w-full touch-none rounded-xl border-2 border-dashed border-gray-300 bg-white"
          @mousedown="begin"
          @mousemove="stroke"
          @mouseup="end"
          @mouseleave="end"
          @touchstart="begin"
          @touchmove="stroke"
          @touchend="end"
        ></canvas>

        <div class="mt-4 flex gap-3">
          <button
            type="button"
            class="flex-1 rounded-base border border-gray-300 py-3 font-medium text-gray-700"
            @click="clear"
          >
            Clear
          </button>
          <button
            type="button"
            :disabled="!hasDrawing || saving"
            class="flex-1 rounded-base gradient-main py-3 font-semibold text-white disabled:opacity-50"
            @click="save"
          >
            {{ saving ? "Sending…" : "Send to CloudVault" }}
          </button>
        </div>
      </template>
    </main>
  </div>
</template>
