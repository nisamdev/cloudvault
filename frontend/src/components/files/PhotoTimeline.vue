<script setup>
import { computed } from "vue";

/**
 * Right-edge scrubber for the photo timeline — years and months, Google Photos
 * style. Clicking jumps the matching day section into view.
 */
const props = defineProps({
  /** Loaded photos, newest-first or otherwise — order does not matter. */
  photos: { type: Array, default: () => [] },
  captureDate: { type: Function, required: true },
});

const emit = defineEmits(["jump"]);

const ticks = computed(() => {
  const byYear = new Map();

  for (const photo of props.photos) {
    const raw = props.captureDate(photo);
    if (!raw) continue;
    const date = new Date(raw);
    if (Number.isNaN(date.getTime())) continue;

    const year = date.getFullYear();
    const month = date.getMonth();
    if (!byYear.has(year)) byYear.set(year, new Set());
    byYear.get(year).add(month);
  }

  return [...byYear.keys()]
    .sort((a, b) => b - a)
    .map((year) => ({
      year,
      months: [...byYear.get(year)]
        .sort((a, b) => b - a)
        .map((month) => ({
          month,
          label: new Date(year, month, 1).toLocaleDateString(undefined, { month: "short" }),
          key: `${year}-${month}`,
        })),
    }));
});

function jump(year, month) {
  emit("jump", { year, month });
}
</script>

<template>
  <nav
    v-if="ticks.length > 1 || (ticks[0] && ticks[0].months.length > 1)"
    class="pointer-events-none fixed bottom-24 right-3 top-28 z-20 hidden w-14 flex-col items-end justify-center xl:flex"
    aria-label="Photo timeline"
  >
    <div
      class="pointer-events-auto max-h-full overflow-y-auto rounded-lg border border-gray-200 bg-white/95 py-2 shadow-md backdrop-blur"
    >
      <div v-for="tick in ticks" :key="tick.year" class="px-2 py-1">
        <button
          type="button"
          class="block w-full rounded px-1.5 py-0.5 text-left text-caption font-bold text-gray-800 transition hover:bg-primary-50 hover:text-primary-700"
          :title="`Jump to ${tick.year}`"
          @click="jump(tick.year, tick.months[0]?.month ?? 0)"
        >
          {{ tick.year }}
        </button>
        <button
          v-for="m in tick.months"
          :key="m.key"
          type="button"
          class="block w-full rounded px-1.5 py-0.5 text-left text-[11px] text-gray-500 transition hover:bg-primary-50 hover:text-primary-700"
          :title="`Jump to ${m.label} ${tick.year}`"
          @click="jump(tick.year, m.month)"
        >
          {{ m.label }}
        </button>
      </div>
    </div>
  </nav>
</template>
