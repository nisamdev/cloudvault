<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from "vue";
import api from "@/api/client";

/**
 * Says where a photograph was taken.
 *
 * Almost nothing arrives with GPS still attached — phones strip it on sharing
 * and anything that came through a messaging app has had it removed — so the
 * only way this vault will ever know is if somebody tells it.
 *
 * The search goes to OpenStreetMap's public geocoder. The words typed here are
 * the only thing that leaves: never the photograph, never its existing
 * coordinates, never anything about the vault. The map underneath is public
 * tile imagery, drawn from the coordinates that came back.
 */
const props = defineProps({
  file: { type: Object, required: true },
});
const emit = defineEmits(["close", "saved"]);

const GEOCODER = "https://nominatim.openstreetmap.org/search";
const TILES = "https://tile.openstreetmap.org";
const ZOOM = 14;
// Three across and three down, which is enough to recognise somewhere.
const GRID = [-1, 0, 1];

const term = ref("");
const results = ref([]);
const searching = ref(false);
const saving = ref(false);
const error = ref("");
const chosen = ref(
  props.file.image?.place_name
    ? {
        name: props.file.image.place_name,
        lat: props.file.image.location?.latitude ?? null,
        lon: props.file.image.location?.longitude ?? null,
      }
    : null,
);

const dialog = ref(null);
const searchBox = ref(null);
let previouslyFocused = null;

/** Which tile a coordinate falls in, and where inside it. */
const centre = computed(() => {
  if (chosen.value?.lat == null || chosen.value?.lon == null) return null;

  const n = 2 ** ZOOM;
  const latRad = (chosen.value.lat * Math.PI) / 180;
  const x = ((chosen.value.lon + 180) / 360) * n;
  const y = ((1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI) / 2) * n;

  return { x: Math.floor(x), y: Math.floor(y), fx: x % 1, fy: y % 1 };
});

const tiles = computed(() => {
  if (!centre.value) return [];

  return GRID.flatMap((dy) =>
    GRID.map((dx) => ({
      key: `${dx},${dy}`,
      url: `${TILES}/${ZOOM}/${centre.value.x + dx}/${centre.value.y + dy}.png`,
    })),
  );
});

/** Where the pin sits over that 3×3 grid, as a percentage. */
const pin = computed(() => {
  if (!centre.value) return null;

  return {
    left: `${((1 + centre.value.fx) / 3) * 100}%`,
    top: `${((1 + centre.value.fy) / 3) * 100}%`,
  };
});

async function search() {
  const query = term.value.trim();
  if (!query) return;

  searching.value = true;
  error.value = "";
  results.value = [];

  try {
    // No API key and no account: OpenStreetMap asks only for modest use, which
    // is why this searches on demand rather than on every keystroke.
    const url = `${GEOCODER}?format=jsonv2&limit=6&q=${encodeURIComponent(query)}`;
    const response = await fetch(url, { headers: { Accept: "application/json" } });
    if (!response.ok) throw new Error("search failed");

    results.value = (await response.json()).map((place) => ({
      name: place.display_name,
      short: place.name || place.display_name.split(",")[0],
      lat: Number(place.lat),
      lon: Number(place.lon),
    }));

    if (!results.value.length) error.value = `Nothing found for “${query}”.`;
  } catch {
    error.value = "Couldn't reach the map search. You can still type a place name below.";
  } finally {
    searching.value = false;
  }
}

function choose(place) {
  chosen.value = { name: place.short, lat: place.lat, lon: place.lon };
  results.value = [];
}

async function save() {
  saving.value = true;
  error.value = "";

  try {
    const { data } = await api.patch(`/files/${props.file.id}`, {
      place_name: chosen.value?.name || "",
      latitude: chosen.value?.lat ?? null,
      longitude: chosen.value?.lon ?? null,
    });
    emit("saved", data.file);
    emit("close");
  } catch (e) {
    error.value = e.userMessage;
    saving.value = false;
  }
}

function clear() {
  chosen.value = null;
  results.value = [];
  term.value = "";
}

function onKeydown(event) {
  if (event.key === "Escape") emit("close");
}

onMounted(async () => {
  previouslyFocused = document.activeElement;
  await nextTick();
  searchBox.value?.focus();
  document.addEventListener("keydown", onKeydown);
});

onBeforeUnmount(() => {
  document.removeEventListener("keydown", onKeydown);
  previouslyFocused?.focus?.();
});
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-gray-900/50 p-4"
    @click.self="emit('close')"
  >
    <div
      ref="dialog"
      class="w-full max-w-lg rounded-xl bg-white shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-labelledby="place-title"
    >
      <header class="flex items-start justify-between border-b border-gray-200 p-6">
        <div class="min-w-0">
          <h2 id="place-title" class="text-h3 font-semibold text-gray-800">Where was this taken?</h2>
          <p class="mt-1 truncate text-body-sm text-gray-500">{{ file.name }}</p>
        </div>
        <button
          type="button"
          class="ml-3 shrink-0 rounded-md p-2 text-gray-400 hover:bg-gray-100 hover:text-gray-600"
          aria-label="Close"
          @click="emit('close')"
        >
          <i class="fas fa-xmark" aria-hidden="true"></i>
        </button>
      </header>

      <div class="space-y-4 p-6">
        <form class="flex gap-2" novalidate @submit.prevent="search">
          <label for="place-search" class="sr-only">Search for a place</label>
          <input
            id="place-search"
            ref="searchBox"
            v-model="term"
            type="search"
            placeholder="Edmonton, or Kulay Way SW…"
            class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          />
          <button
            type="submit"
            :disabled="searching || !term.trim()"
            class="shrink-0 rounded-base bg-primary-600 px-4 py-2 text-body-sm font-semibold text-white transition hover:bg-primary-700 disabled:opacity-60"
          >
            {{ searching ? "…" : "Search" }}
          </button>
        </form>

        <p
          v-if="error"
          role="alert"
          class="rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
        >
          {{ error }}
        </p>

        <ul v-if="results.length" class="max-h-56 divide-y divide-gray-100 overflow-y-auto rounded-base border border-gray-200">
          <li v-for="place in results" :key="`${place.lat},${place.lon}`">
            <button
              type="button"
              class="flex w-full items-start gap-3 px-3 py-2 text-left transition hover:bg-gray-50"
              @click="choose(place)"
            >
              <i class="fas fa-location-dot mt-1 text-gray-400" aria-hidden="true"></i>
              <span class="min-w-0">
                <span class="block truncate text-body-sm font-medium text-gray-800">
                  {{ place.short }}
                </span>
                <span class="block truncate text-caption text-gray-500">{{ place.name }}</span>
              </span>
            </button>
          </li>
        </ul>

        <!-- What was picked, over public map imagery. Confirmation, not a map
             to navigate: the pin is where the photograph will be filed. -->
        <div v-if="chosen">
          <div
            v-if="tiles.length"
            class="relative aspect-[3/2] overflow-hidden rounded-base border border-gray-200 bg-gray-100"
          >
            <div class="absolute inset-0 grid grid-cols-3 grid-rows-3">
              <img
                v-for="tile in tiles"
                :key="tile.key"
                :src="tile.url"
                alt=""
                loading="lazy"
                class="h-full w-full object-cover"
              />
            </div>
            <i
              v-if="pin"
              class="fas fa-location-dot absolute -translate-x-1/2 -translate-y-full text-2xl text-error-600 drop-shadow"
              :style="pin"
              aria-hidden="true"
            ></i>
          </div>

          <div class="mt-3 flex items-start justify-between gap-3">
            <label for="place-name" class="min-w-0 flex-1">
              <span class="mb-1 block text-caption uppercase tracking-wider text-gray-500">
                Filed as
              </span>
              <input
                id="place-name"
                v-model="chosen.name"
                type="text"
                class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
              />
            </label>
            <button
              type="button"
              class="mt-6 shrink-0 text-body-sm font-medium text-gray-500 hover:text-gray-700"
              @click="clear"
            >
              Clear
            </button>
          </div>
          <p class="mt-1 text-caption text-gray-500">
            This is the name you'll search by. Change it to whatever you'd actually call it.
          </p>
        </div>

        <p v-else class="text-caption text-gray-500">
          Only the words you type are sent to OpenStreetMap to find a place. The photograph never
          leaves your vault.
        </p>
      </div>

      <footer class="flex justify-end gap-3 border-t border-gray-200 p-6">
        <button
          type="button"
          class="rounded-base border border-gray-300 px-4 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
          @click="emit('close')"
        >
          Cancel
        </button>
        <button
          type="button"
          :disabled="saving"
          class="rounded-base bg-primary-600 px-4 py-2 text-body-sm font-semibold text-white transition hover:bg-primary-700 disabled:opacity-60"
          @click="save"
        >
          {{ saving ? "Saving…" : chosen ? "Save this place" : "Remove the place" }}
        </button>
      </footer>
    </div>
  </div>
</template>
