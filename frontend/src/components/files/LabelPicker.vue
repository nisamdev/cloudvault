<script setup>
import { ref } from "vue";
import api from "@/api/client";
import { useLibraryStore } from "@/stores/library";
import { useFilesStore } from "@/stores/files";

const props = defineProps({
  file: { type: Object, required: true },
});
const emit = defineEmits(["close"]);

const library = useLibraryStore();
const filesStore = useFilesStore();

const selected = ref(props.file.labels.map((l) => l.id));
const newLabelName = ref("");
const saving = ref(false);
const error = ref("");

// Palette from DESIGN_TOKENS.md; cycles as labels are added.
const COLORS = ["#4F46E5", "#9333EA", "#EC4899", "#10B981", "#F59E0B", "#EF4444", "#3B82F6", "#6B7280"];

function toggle(labelId) {
  const index = selected.value.indexOf(labelId);
  if (index >= 0) selected.value.splice(index, 1);
  else selected.value.push(labelId);
}

async function addLabel() {
  const name = newLabelName.value.trim();
  if (!name) return;

  error.value = "";
  try {
    const label = await library.createLabel({
      name,
      color: COLORS[library.labels.length % COLORS.length],
    });
    selected.value.push(label.id);
    newLabelName.value = "";
  } catch (e) {
    error.value = e.userMessage;
  }
}

async function save() {
  saving.value = true;
  error.value = "";

  try {
    const { data } = await api.patch(`/files/${props.file.id}`, { label_ids: selected.value });

    const index = filesStore.items.findIndex((f) => f.id === data.file.id);
    if (index >= 0) filesStore.items.splice(index, 1, data.file);

    // Counts on the label list are now stale.
    library.fetchLabels();
    emit("close");
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <div
    class="fixed inset-0 z-40 flex items-center justify-center bg-gray-900/50 p-4"
    @click.self="emit('close')"
  >
    <div
      class="w-full max-w-md rounded-xl bg-white shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-labelledby="label-picker-title"
    >
      <header class="flex items-start justify-between border-b border-gray-200 p-6">
        <div class="min-w-0">
          <h2 id="label-picker-title" class="text-h3 font-semibold text-gray-800">Labels</h2>
          <p class="mt-1 truncate text-body-sm text-gray-500">{{ file.name }}</p>
        </div>
        <button
          type="button"
          class="rounded-md p-2 text-gray-400 hover:bg-gray-100 hover:text-gray-600"
          aria-label="Close labels dialog"
          @click="emit('close')"
        >
          <i class="fas fa-xmark" aria-hidden="true"></i>
        </button>
      </header>

      <div class="space-y-4 p-6">
        <p
          v-if="error"
          role="alert"
          class="rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
        >
          {{ error }}
        </p>

        <p v-if="!library.labels.length" class="text-body-sm text-gray-500">
          No labels yet. Create one below.
        </p>

        <ul v-else class="max-h-56 space-y-1 overflow-y-auto">
          <li v-for="label in library.labels" :key="label.id">
            <label class="flex cursor-pointer items-center gap-3 rounded-base px-2 py-2 hover:bg-gray-50">
              <input
                type="checkbox"
                :checked="selected.includes(label.id)"
                class="rounded border-gray-300 text-primary-600 focus:ring-primary-500"
                @change="toggle(label.id)"
              />
              <span
                class="h-3 w-3 shrink-0 rounded-full"
                :style="{ backgroundColor: label.color }"
                aria-hidden="true"
              ></span>
              <span class="flex-1 truncate text-body-sm text-gray-700">{{ label.name }}</span>
              <span class="text-caption text-gray-400">{{ label.files_count }}</span>
            </label>
          </li>
        </ul>

        <form class="flex gap-2 border-t border-gray-200 pt-4" @submit.prevent="addLabel">
          <label for="new-label" class="sr-only">New label name</label>
          <input
            id="new-label"
            v-model="newLabelName"
            type="text"
            maxlength="40"
            placeholder="New label…"
            class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          />
          <button
            type="submit"
            :disabled="!newLabelName.trim()"
            class="shrink-0 rounded-base border border-gray-300 px-3 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50 disabled:opacity-50"
          >
            Add
          </button>
        </form>
      </div>

      <footer class="flex justify-end gap-3 border-t border-gray-200 p-6">
        <button
          type="button"
          class="rounded-base border border-gray-300 px-4 py-2 text-body-sm font-medium text-gray-700 hover:bg-gray-50"
          @click="emit('close')"
        >
          Cancel
        </button>
        <button
          type="button"
          :disabled="saving"
          class="rounded-base gradient-main px-4 py-2 text-body-sm font-semibold text-white transition hover:opacity-95 disabled:opacity-60"
          @click="save"
        >
          {{ saving ? "Saving…" : "Save labels" }}
        </button>
      </footer>
    </div>
  </div>
</template>
