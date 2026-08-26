<script setup>
import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch } from "vue";
import {
  FILTERS,
  FULL_FRAME,
  applyFilter,
  croppedSize,
  detectPage,
  toCanvas,
  warp,
} from "@/utils/scanner";

/**
 * One page, with its crop and its look.
 *
 * The left pane is the photograph with the crop drawn over it; the right is
 * what the page will actually be. Both come out of the same functions the save
 * uses, so what is on screen is what lands in the file — at a lower resolution,
 * which is the only difference.
 */
const props = defineProps({
  page: { type: Object, required: true },
  /** The loaded original. Kept by the parent, since it owns the page list. */
  image: { type: Object, required: true },
  index: { type: Number, required: true },
  total: { type: Number, required: true },
});

const emit = defineEmits(["change", "apply-to-all"]);

// Big enough to drag against accurately, small enough that a 12MP photo does
// not sit in memory four times over.
const SOURCE_DIMENSION = 1400;
const PREVIEW_DIMENSION = 700;

const sourceCanvas = ref(null);
const previewCanvas = ref(null);
const detecting = ref(false);

// The photograph, rotated and scaled — the thing the corners are relative to.
// Shallow: it holds a canvas, which must not be handed out through a proxy.
const working = shallowRef(null);
let previewHandle = null;

const corners = computed(() => props.page.corners ?? FULL_FRAME);

const cropIsFullFrame = computed(() =>
  corners.value.every((corner, i) => corner.x === FULL_FRAME[i].x && corner.y === FULL_FRAME[i].y),
);

/** Handle size in source pixels, so it stays about the same size on screen. */
const handleRadius = computed(() =>
  working.value ? Math.max(working.value.width, working.value.height) * 0.016 : 10,
);

const scaleX = computed(() => working.value?.width ?? 1);
const scaleY = computed(() => working.value?.height ?? 1);

const polygon = computed(() =>
  corners.value.map((corner) => `${corner.x * scaleX.value},${corner.y * scaleY.value}`).join(" "),
);

/**
 * The frame with the crop cut out of it, as one path — two subpaths and the
 * even-odd rule, which is what makes the hole a hole. Two separate shapes would
 * just paint one over the other.
 */
const shadePath = computed(() => {
  const outer = `M0,0 H${scaleX.value} V${scaleY.value} H0 Z`;
  const inner = corners.value
    .map((corner, i) => `${i === 0 ? "M" : "L"}${corner.x * scaleX.value},${corner.y * scaleY.value}`)
    .join(" ");

  return `${outer} ${inner} Z`;
});

/** Midpoints, which drag a whole side in or out — the usual margin trim. */
const edgeHandles = computed(() =>
  corners.value.map((corner, index) => {
    const next = corners.value[(index + 1) % 4];
    return {
      index,
      x: ((corner.x + next.x) / 2) * scaleX.value,
      y: ((corner.y + next.y) / 2) * scaleY.value,
    };
  }),
);

/* ------------------------------------------------------------- rendering */

function drawSource() {
  const rendered = toCanvas(props.image, {
    rotation: props.page.rotation ?? 0,
    maxDimension: SOURCE_DIMENSION,
  });
  working.value = rendered;

  const canvas = sourceCanvas.value;
  if (!canvas) return;

  canvas.width = rendered.width;
  canvas.height = rendered.height;
  canvas.getContext("2d").drawImage(rendered, 0, 0);
}

/**
 * Redraws the result. Scheduled rather than immediate: dragging a corner fires
 * dozens of times a second and each pass is a full warp.
 */
function schedulePreview() {
  if (previewHandle) cancelAnimationFrame(previewHandle);

  previewHandle = requestAnimationFrame(() => {
    previewHandle = null;
    drawPreview();
  });
}

function drawPreview() {
  const canvas = previewCanvas.value;
  const source = working.value;
  if (!canvas || !source) return;

  const size = croppedSize(corners.value, source.width, source.height, PREVIEW_DIMENSION);
  const result = warp(source, corners.value, size);
  applyFilter(result, props.page);

  canvas.width = result.width;
  canvas.height = result.height;
  canvas.getContext("2d").putImageData(result, 0, 0);
}

// Not an immediate watcher: that runs before the canvases are bound, and would
// silently draw the first page into nothing.
onMounted(() => {
  drawSource();
  schedulePreview();
});

watch(
  () => [props.page.id, props.page.rotation],
  () => {
    drawSource();
    schedulePreview();
  },
);

watch(
  () => [props.page.filter, props.page.brightness, props.page.contrast, props.page.corners],
  schedulePreview,
  { deep: true },
);

onBeforeUnmount(() => {
  if (previewHandle) cancelAnimationFrame(previewHandle);
});

/* ------------------------------------------------------------ the corners */

let dragging = null;

function pointerPosition(event, element) {
  const box = element.getBoundingClientRect();

  return {
    x: Math.min(1, Math.max(0, (event.clientX - box.left) / box.width)),
    y: Math.min(1, Math.max(0, (event.clientY - box.top) / box.height)),
  };
}

function startCorner(event, index) {
  event.preventDefault();
  event.currentTarget.setPointerCapture(event.pointerId);
  dragging = { kind: "corner", index };
}

function startEdge(event, index) {
  event.preventDefault();
  event.currentTarget.setPointerCapture(event.pointerId);
  dragging = { kind: "edge", index, from: pointerPosition(event, event.currentTarget.ownerSVGElement) };
}

function onPointerMove(event) {
  if (!dragging) return;

  const position = pointerPosition(event, event.currentTarget);
  const next = corners.value.map((corner) => ({ ...corner }));

  if (dragging.kind === "corner") {
    next[dragging.index] = position;
  } else {
    // Both ends of the side move together, by however far the pointer has come
    // since the drag started.
    const dx = position.x - dragging.from.x;
    const dy = position.y - dragging.from.y;
    const other = (dragging.index + 1) % 4;

    next[dragging.index] = clampPoint(next[dragging.index], dx, dy);
    next[other] = clampPoint(next[other], dx, dy);
    dragging.from = position;
  }

  emit("change", { corners: next });
}

function clampPoint(corner, dx, dy) {
  return {
    x: Math.min(1, Math.max(0, corner.x + dx)),
    y: Math.min(1, Math.max(0, corner.y + dy)),
  };
}

function endDrag() {
  dragging = null;
}

/* -------------------------------------------------------------- controls */

function autoDetect() {
  if (!working) return;

  detecting.value = true;
  // Yielding first lets the button show it was pressed; detection blocks.
  requestAnimationFrame(() => {
    try {
      emit("change", { corners: detectPage(working.value) });
    } finally {
      detecting.value = false;
    }
  });
}

function resetCrop() {
  emit("change", { corners: FULL_FRAME.map((corner) => ({ ...corner })) });
}

function rotate(degrees) {
  const rotation = (((props.page.rotation ?? 0) + degrees) % 360 + 360) % 360;

  // The crop is expressed in the rotated frame, so it no longer means what it
  // did. Turning the corners with the image keeps the page selected.
  emit("change", { rotation, corners: turnCorners(corners.value, degrees) });
}

function turnCorners(current, degrees) {
  const turned = current.map((corner) =>
    degrees === 90 ? { x: 1 - corner.y, y: corner.x } : { x: corner.y, y: 1 - corner.x },
  );

  // Keep them in clockwise-from-top-left order, or the handles swap places.
  return degrees === 90
    ? [turned[3], turned[0], turned[1], turned[2]]
    : [turned[1], turned[2], turned[3], turned[0]];
}
</script>

<template>
  <div class="rounded-lg border border-gray-200 bg-white p-4">
    <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
      <h3 class="text-body font-semibold text-gray-800">
        Page {{ index + 1 }}
        <span class="font-normal text-gray-400">of {{ total }}</span>
      </h3>

      <div class="flex flex-wrap items-center gap-1">
        <button
          type="button"
          class="rounded-base border border-gray-300 px-2.5 py-1.5 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
          aria-label="Rotate left"
          @click="rotate(-90)"
        >
          <i class="fas fa-rotate-left" aria-hidden="true"></i>
        </button>
        <button
          type="button"
          class="rounded-base border border-gray-300 px-2.5 py-1.5 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
          aria-label="Rotate right"
          @click="rotate(90)"
        >
          <i class="fas fa-rotate-right" aria-hidden="true"></i>
        </button>
        <button
          type="button"
          :disabled="detecting"
          class="rounded-base border border-gray-300 px-2.5 py-1.5 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50 disabled:opacity-60"
          @click="autoDetect"
        >
          <i class="fas fa-crop-simple mr-1.5" aria-hidden="true"></i>Find the page
        </button>
        <button
          type="button"
          :disabled="cropIsFullFrame"
          class="rounded-base border border-gray-300 px-2.5 py-1.5 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50 disabled:opacity-40"
          @click="resetCrop"
        >
          Whole photo
        </button>
      </div>
    </div>

    <div class="grid gap-4 lg:grid-cols-2">
      <!-- The photograph, with the crop over it -->
      <div>
        <p class="mb-1.5 text-label font-medium uppercase tracking-wide text-gray-500">
          Drag the corners or the sides
        </p>

        <div class="relative overflow-hidden rounded-base bg-gray-900">
          <canvas ref="sourceCanvas" class="block w-full"></canvas>

          <svg
            v-if="working"
            class="absolute inset-0 h-full w-full touch-none"
            :viewBox="`0 0 ${working.width} ${working.height}`"
            preserveAspectRatio="none"
            role="application"
            aria-label="Crop area. Drag the corner or side handles to change it."
            @pointermove="onPointerMove"
            @pointerup="endDrag"
            @pointercancel="endDrag"
          >
            <!-- Everything outside the crop, dimmed: the page reads as the part
                 that is still lit. -->
            <path :d="shadePath" fill="rgba(15, 23, 42, 0.55)" fill-rule="evenodd" />
            <polygon
              :points="polygon"
              fill="none"
              stroke="var(--color-primary-400)"
              stroke-width="2"
              vector-effect="non-scaling-stroke"
            />

            <circle
              v-for="edge in edgeHandles"
              :key="`edge-${edge.index}`"
              :cx="edge.x"
              :cy="edge.y"
              :r="handleRadius * 0.75"
              class="cursor-move"
              fill="var(--color-primary-400)"
              stroke="white"
              stroke-width="2"
              vector-effect="non-scaling-stroke"
              @pointerdown="startEdge($event, edge.index)"
            />

            <circle
              v-for="(corner, i) in corners"
              :key="`corner-${i}`"
              :cx="corner.x * working.width"
              :cy="corner.y * working.height"
              :r="handleRadius"
              class="cursor-grab"
              fill="white"
              stroke="var(--color-primary-600)"
              stroke-width="3"
              vector-effect="non-scaling-stroke"
              @pointerdown="startCorner($event, i)"
            />
          </svg>
        </div>
      </div>

      <!-- What it will be -->
      <div>
        <p class="mb-1.5 text-label font-medium uppercase tracking-wide text-gray-500">
          The page
        </p>

        <div class="flex items-center justify-center rounded-base border border-gray-200 bg-gray-50 p-3">
          <canvas ref="previewCanvas" class="max-h-[22rem] w-auto max-w-full shadow-sm"></canvas>
        </div>
      </div>
    </div>

    <!-- Look -->
    <fieldset class="mt-4">
      <legend class="mb-1.5 text-label font-medium uppercase tracking-wide text-gray-500">
        Look
      </legend>

      <div class="flex flex-wrap gap-2">
        <button
          v-for="option in FILTERS"
          :key="option.value"
          type="button"
          :aria-pressed="page.filter === option.value"
          :title="option.hint"
          :class="[
            'rounded-base border px-3 py-1.5 text-body-sm font-medium transition',
            page.filter === option.value
              ? 'border-primary-600 bg-primary-50 text-primary-700'
              : 'border-gray-300 text-gray-600 hover:bg-gray-50',
          ]"
          @click="emit('change', { filter: option.value })"
        >
          {{ option.label }}
        </button>
      </div>

      <p class="mt-1.5 text-caption text-gray-500">
        {{ FILTERS.find((f) => f.value === page.filter)?.hint }}
      </p>
    </fieldset>

    <div class="mt-4 grid gap-4 sm:grid-cols-2">
      <div>
        <label :for="`brightness-${page.id}`" class="mb-1 flex justify-between text-body-sm text-gray-700">
          <span>Brightness</span>
          <span class="tabular-nums text-gray-400">{{ page.brightness }}</span>
        </label>
        <input
          :id="`brightness-${page.id}`"
          type="range"
          min="-60"
          max="60"
          :value="page.brightness"
          class="w-full accent-primary-600"
          @input="emit('change', { brightness: Number($event.target.value) })"
        />
      </div>

      <div>
        <label :for="`contrast-${page.id}`" class="mb-1 flex justify-between text-body-sm text-gray-700">
          <span>Contrast</span>
          <span class="tabular-nums text-gray-400">{{ page.contrast }}</span>
        </label>
        <input
          :id="`contrast-${page.id}`"
          type="range"
          min="-60"
          max="60"
          :value="page.contrast"
          class="w-full accent-primary-600"
          @input="emit('change', { contrast: Number($event.target.value) })"
        />
      </div>
    </div>

    <div v-if="total > 1" class="mt-4 flex flex-wrap items-center gap-3 border-t border-gray-100 pt-3">
      <button
        type="button"
        class="text-body-sm font-medium text-primary-600 transition hover:underline"
        @click="emit('apply-to-all')"
      >
        <i class="fas fa-wand-magic-sparkles mr-1.5" aria-hidden="true"></i>
        Use this look on every page
      </button>
      <span class="text-caption text-gray-400">The crop stays per page.</span>
    </div>
  </div>
</template>
