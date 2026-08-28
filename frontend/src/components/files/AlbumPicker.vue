<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from "vue";

/**
 * Which album to file photographs under.
 *
 * Typing the name of a folder you already have is the wrong way round — the
 * app knows them and should offer them. Search narrows the list; a name that
 * matches nothing offers to become one.
 */
const props = defineProps({
  albums: { type: Array, required: true },
  count: { type: Number, default: 1 },
  /** The album these are in already, which is not worth offering. */
  currentId: { type: [Number, String], default: null },
});
const emit = defineEmits(["choose", "create", "close"]);

const term = ref("");
const searchBox = ref(null);
let previouslyFocused = null;

const matches = computed(() => {
  const needle = term.value.trim().toLowerCase();
  const offerable = props.albums.filter((a) => a.id !== props.currentId);

  return needle ? offerable.filter((a) => a.name.toLowerCase().includes(needle)) : offerable;
});

/** Only worth offering when it is not one you already have. */
const canCreate = computed(() => {
  const wanted = term.value.trim();
  if (!wanted) return false;

  return !props.albums.some((a) => a.name.toLowerCase() === wanted.toLowerCase());
});

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
      class="flex max-h-[80vh] w-full max-w-md flex-col rounded-xl bg-white shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-labelledby="album-picker-title"
    >
      <header class="border-b border-gray-200 p-6 pb-4">
        <h2 id="album-picker-title" class="text-h3 font-semibold text-gray-800">
          Put {{ count }} {{ count === 1 ? "photo" : "photos" }} in…
        </h2>

        <label for="album-search" class="sr-only">Search albums</label>
        <input
          id="album-search"
          ref="searchBox"
          v-model="term"
          type="search"
          placeholder="Search, or type a new album name"
          class="mt-3 w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          @keydown.enter.prevent="canCreate ? emit('create', term.trim()) : matches[0] && emit('choose', matches[0].id)"
        />
      </header>

      <ul class="min-h-0 flex-1 overflow-y-auto p-2">
        <li v-for="album in matches" :key="album.id">
          <button
            type="button"
            class="flex w-full items-center gap-3 rounded-base px-3 py-2.5 text-left transition hover:bg-gray-50"
            @click="emit('choose', album.id)"
          >
            <i
              :class="['fas w-4 text-gray-400', album.is_default ? 'fa-images' : 'fa-folder']"
              aria-hidden="true"
            ></i>
            <span class="min-w-0 flex-1 truncate text-body-sm text-gray-800">{{ album.name }}</span>
            <span class="shrink-0 text-caption tabular-nums text-gray-400">
              {{ album.file_count }}
            </span>
          </button>
        </li>

        <li v-if="canCreate">
          <button
            type="button"
            class="flex w-full items-center gap-3 rounded-base px-3 py-2.5 text-left transition hover:bg-primary-50"
            @click="emit('create', term.trim())"
          >
            <i class="fas w-4 fa-plus text-primary-600" aria-hidden="true"></i>
            <span class="min-w-0 flex-1 truncate text-body-sm font-medium text-primary-700">
              New album “{{ term.trim() }}”
            </span>
          </button>
        </li>

        <!-- "No albums" would be a lie when the only one is the album these
             are already in. Say which it is. -->
        <li v-else-if="!matches.length" class="px-3 py-6 text-center text-body-sm text-gray-500">
          <template v-if="term.trim()">Nothing matches “{{ term.trim() }}”.</template>
          <template v-else-if="albums.length">
            Already in {{ albums.find((a) => a.id === currentId)?.name ?? "this album" }}. Type a
            name to make another.
          </template>
          <template v-else>No albums yet. Type a name to make one.</template>
        </li>
      </ul>

      <footer class="flex justify-end border-t border-gray-200 p-4">
        <button
          type="button"
          class="rounded-base border border-gray-300 px-4 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
          @click="emit('close')"
        >
          Cancel
        </button>
      </footer>
    </div>
  </div>
</template>
