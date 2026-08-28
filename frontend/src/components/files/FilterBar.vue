<script setup>
import { computed, onMounted, ref } from "vue";
import api from "@/api/client";
import { useAuthStore } from "@/stores/auth";
import { useLibraryStore } from "@/stores/library";

const props = defineProps({
  modelValue: { type: Object, required: true },
  // Shape and location only mean something for photos.
  photoFilters: { type: Boolean, default: false },
  // Capture-date sorting likewise.
  captureSort: { type: Boolean, default: false },
});
const emit = defineEmits(["update:modelValue", "change"]);

const auth = useAuthStore();
const library = useLibraryStore();

const members = ref([]);
const expanded = ref(false);
// The preset select must be controlled, or "Clear filters" leaves it showing
// the last preset while nothing is actually filtered.
const preset = ref("");

const BASE_SORTS = [
  { value: "newest", label: "Newest uploaded" },
  { value: "oldest", label: "Oldest uploaded" },
  { value: "name", label: "Name (A–Z)" },
  { value: "largest", label: "Largest first" },
  { value: "smallest", label: "Smallest first" },
];

const CAPTURE_SORTS = [
  { value: "taken_newest", label: "Newest taken" },
  { value: "taken_oldest", label: "Oldest taken" },
];

const SORTS = computed(() =>
  props.captureSort ? [...BASE_SORTS.slice(0, 2), ...CAPTURE_SORTS, ...BASE_SORTS.slice(2)] : BASE_SORTS,
);

const ORIENTATIONS = [
  { value: "", label: "Any shape" },
  { value: "landscape", label: "Landscape" },
  { value: "portrait", label: "Portrait" },
  { value: "square", label: "Square" },
];

// Presets cover the common cases; the two date fields handle everything else.
const DATE_PRESETS = [
  { value: "", label: "Any time" },
  { value: "0", label: "Today" },
  { value: "1", label: "Last 2 days" },
  { value: "7", label: "Last 7 days" },
  { value: "30", label: "Last 30 days" },
  { value: "365", label: "Last year" },
];

const filters = computed({
  get: () => props.modelValue,
  set: (value) => emit("update:modelValue", value),
});

// Everything except sort, which is always set and is not really a "filter".
// Human-readable summary of what is applied, each removable on its own.
const activeChips = computed(() => {
  const f = props.modelValue;
  const chips = [];

  if (f.date_from || f.date_to) {
    const from = f.date_from ? new Date(f.date_from).toLocaleDateString() : "any";
    const to = f.date_to ? new Date(f.date_to).toLocaleDateString() : "now";
    chips.push({ key: "date", label: `${from} – ${to}`, clear: { date_from: "", date_to: "" } });
  }

  if (f.owner_id) {
    const member = members.value.find((m) => String(m.user.id) === String(f.owner_id));
    chips.push({
      key: "owner",
      label: `By ${member?.user.full_name || member?.user.email || "someone"}`,
      clear: { owner_id: "" },
    });
  }

  if (f.visibility) {
    chips.push({
      key: "visibility",
      label: f.visibility === "family" ? "Shared with family" : "Only me",
      clear: { visibility: "" },
    });
  }

  if (f.orientation) {
    chips.push({ key: "orientation", label: f.orientation, clear: { orientation: "" } });
  }

  if (f.place) {
    chips.push({ key: "place", label: `Place: ${f.place}`, clear: { place: "" } });
  }
  if (f.has_location) {
    chips.push({ key: "location", label: "Pinned on a map", clear: { has_location: "" } });
  }

  for (const id of f.label_ids ?? []) {
    const label = library.labels.find((l) => l.id === id);
    if (label) {
      chips.push({
        key: `label-${id}`,
        label: label.name,
        color: label.color,
        clear: { label_ids: (f.label_ids ?? []).filter((x) => x !== id) },
      });
    }
  }

  return chips;
});

const activeCount = computed(() => {
  const f = props.modelValue;
  return [
    f.owner_id,
    f.visibility,
    f.orientation,
    f.has_location,
    f.place,
    f.date_from,
    f.date_to,
    f.label_ids?.length ? "1" : "",
  ].filter(Boolean).length;
});

onMounted(async () => {
  library.fetchLabels();
  if (!auth.family) return;

  try {
    const { data } = await api.get(`/families/${auth.family.id}`);
    members.value = data.members;
  } catch {
    // The owner filter simply stays empty if the family can't be loaded.
  }
});

function update(patch) {
  filters.value = { ...props.modelValue, ...patch };
  emit("change");
}

function applyPreset(days) {
  // "0" means today, which is falsy as a number — check for the empty option.
  if (days === "" || days === null || days === undefined) {
    update({ date_from: "", date_to: "" });
    return;
  }

  const from = new Date();
  from.setDate(from.getDate() - Number(days));
  update({ date_from: from.toISOString().slice(0, 10), date_to: "" });
}

function toggleLabel(id) {
  const current = props.modelValue.label_ids ?? [];
  const next = current.includes(id) ? current.filter((x) => x !== id) : [...current, id];
  update({ label_ids: next });
}

function clearAll() {
  preset.value = "";
  update({
    owner_id: "",
    visibility: "",
    orientation: "",
    has_location: "",
    place: "",
    date_from: "",
    date_to: "",
    label_ids: [],
  });
}
</script>

<template>
  <div class="mb-6 rounded-lg border border-gray-200 bg-white p-4">
    <div class="flex flex-wrap items-center gap-3">
      <div>
        <label for="gallery-sort" class="sr-only">Sort photos</label>
        <select
          id="gallery-sort"
          :value="modelValue.sort"
          class="rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          @change="update({ sort: $event.target.value })"
        >
          <option v-for="option in SORTS" :key="option.value" :value="option.value">
            {{ option.label }}
          </option>
        </select>
      </div>

      <div>
        <label for="gallery-date" class="sr-only">Date range</label>
        <select
          id="gallery-date"
          v-model="preset"
          class="rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          @change="applyPreset($event.target.value)"
        >
          <option v-for="option in DATE_PRESETS" :key="option.value" :value="option.value">
            {{ option.label }}
          </option>
        </select>
      </div>

      <div v-if="auth.family">
        <label for="gallery-owner" class="sr-only">Uploaded by</label>
        <select
          id="gallery-owner"
          :value="modelValue.owner_id"
          class="rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          @change="update({ owner_id: $event.target.value })"
        >
          <option value="">Anyone</option>
          <option v-for="member in members" :key="member.user.id" :value="member.user.id">
            {{ member.user.full_name || member.user.email }}
          </option>
        </select>
      </div>

      <button
        type="button"
        :aria-expanded="expanded"
        class="rounded-base border border-gray-300 px-3 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
        @click="expanded = !expanded"
      >
        <i class="fas fa-sliders mr-2" aria-hidden="true"></i>More filters
        <span
          v-if="activeCount"
          class="ml-2 rounded-full bg-primary-600 px-2 py-0.5 text-caption font-semibold text-white"
        >
          {{ activeCount }}
        </span>
      </button>

      <button
        v-if="activeCount"
        type="button"
        class="text-body-sm font-medium text-primary-600 hover:underline"
        @click="clearAll"
      >
        Clear filters
      </button>
    </div>

    <!-- What is actually applied right now, each chip removable. -->
    <ul v-if="activeChips.length" class="mt-3 flex flex-wrap items-center gap-2">
      <li class="text-caption font-medium uppercase tracking-wide text-gray-400">Filtered by</li>
      <li v-for="chip in activeChips" :key="chip.key">
        <button
          type="button"
          class="flex items-center gap-2 rounded-full bg-primary-50 px-3 py-1 text-body-sm text-primary-700 transition hover:bg-primary-100"
          :aria-label="`Remove filter: ${chip.label}`"
          @click="update(chip.clear)"
        >
          <span
            v-if="chip.color"
            class="h-2.5 w-2.5 rounded-full"
            :style="{ backgroundColor: chip.color }"
            aria-hidden="true"
          ></span>
          {{ chip.label }}
          <i class="fas fa-xmark text-caption" aria-hidden="true"></i>
        </button>
      </li>
    </ul>

    <div v-if="expanded" class="mt-4 grid gap-4 border-t border-gray-200 pt-4 sm:grid-cols-2 lg:grid-cols-4">
      <div>
        <label for="gallery-visibility" class="mb-1 block text-label font-medium text-gray-600">
          Visibility
        </label>
        <select
          id="gallery-visibility"
          :value="modelValue.visibility"
          class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          @change="update({ visibility: $event.target.value })"
        >
          <option value="">Everything I can see</option>
          <option value="private">Only me</option>
          <option value="family">Shared with family</option>
        </select>
      </div>

      <div v-if="photoFilters">
        <label for="gallery-orientation" class="mb-1 block text-label font-medium text-gray-600">
          Shape
        </label>
        <select
          id="gallery-orientation"
          :value="modelValue.orientation"
          class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          @change="update({ orientation: $event.target.value })"
        >
          <option v-for="option in ORIENTATIONS" :key="option.value" :value="option.value">
            {{ option.label }}
          </option>
        </select>
      </div>

      <!-- Searching by place searches what somebody wrote on the photograph,
           not its EXIF: almost none of them arrive knowing where they were. -->
      <div v-if="photoFilters">
        <label for="gallery-place" class="mb-1 block text-label font-medium text-gray-600">
          Place
        </label>
        <input
          id="gallery-place"
          type="search"
          :value="modelValue.place"
          placeholder="Edmonton, the beach…"
          class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          @change="update({ place: $event.target.value })"
        />
      </div>

      <div v-if="photoFilters">
        <label for="gallery-location" class="mb-1 block text-label font-medium text-gray-600">
          Has a place
        </label>
        <select
          id="gallery-location"
          :value="modelValue.has_location"
          class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          @change="update({ has_location: $event.target.value })"
        >
          <option value="">Anywhere</option>
          <option value="true">Pinned on a map</option>
        </select>
      </div>

      <div>
        <label for="gallery-from" class="mb-1 block text-label font-medium text-gray-600">
          Uploaded from
        </label>
        <input
          id="gallery-from"
          type="date"
          :value="modelValue.date_from"
          class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          @change="preset = ''; update({ date_from: $event.target.value })"
        />
      </div>

      <div>
        <label for="gallery-to" class="mb-1 block text-label font-medium text-gray-600">
          Uploaded to
        </label>
        <input
          id="gallery-to"
          type="date"
          :value="modelValue.date_to"
          class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          @change="preset = ''; update({ date_to: $event.target.value })"
        />
      </div>

      <div v-if="library.labels.length" class="sm:col-span-2 lg:col-span-4">
        <p class="mb-2 text-label font-medium text-gray-600">Labels</p>
        <ul class="flex flex-wrap gap-2">
          <li v-for="label in library.labels" :key="label.id">
            <button
              type="button"
              :aria-pressed="(modelValue.label_ids ?? []).includes(label.id)"
              :class="[
                'flex items-center gap-2 rounded-full border px-3 py-1 text-body-sm transition',
                (modelValue.label_ids ?? []).includes(label.id)
                  ? 'border-primary-600 bg-primary-50 text-primary-700'
                  : 'border-gray-300 text-gray-600 hover:bg-gray-50',
              ]"
              @click="toggleLabel(label.id)"
            >
              <span
                class="h-2.5 w-2.5 rounded-full"
                :style="{ backgroundColor: label.color }"
                aria-hidden="true"
              ></span>
              {{ label.name }}
            </button>
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>
