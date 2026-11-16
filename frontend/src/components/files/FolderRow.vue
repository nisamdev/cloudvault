<script setup>
import { computed } from "vue";
import { useLibraryStore } from "@/stores/library";
import { useDragAndDrop } from "@/composables/useDragAndDrop";
import InlineName from "@/components/ui/InlineName.vue";

const props = defineProps({
  folder: { type: Object, required: true },
  // Owned by the view, so only one name anywhere on the screen is being typed.
  editing: { type: Boolean, default: false },
  selected: { type: Boolean, default: false },
  // Once anything is selected, checkboxes stay visible on every row.
  selecting: { type: Boolean, default: false },
  /** "list" is a thin row; "grid" is a tile alongside file tiles. */
  view: { type: String, default: "list" },
});
const emit = defineEmits([
  "open", "drop", "rename", "delete", "download", "update:editing", "select", "menu",
]);

const library = useLibraryStore();
const { dragging, dropTargetId, startDrag, endDrag, onDragOver, onDragLeave } = useDragAndDrop();

// A folder cannot be dropped into itself or into its own subtree.
const descendantIds = computed(() => library.descendantIds(props.folder.id));
const isDropTarget = computed(() => dropTargetId.value === props.folder.id);
const isBeingDragged = computed(
  () => dragging.value?.type === "folder" && dragging.value.id === props.folder.id,
);

function handleDrop(event) {
  event.preventDefault();
  const payload = dragging.value;
  endDrag();
  if (payload) emit("drop", { payload, targetFolderId: props.folder.id });
}

function onSelectClick(event) {
  event.stopPropagation();
  emit("select", event);
}
</script>

<template>
  <!-- Compact row: one thin line, name and count, everything else behind the
       menu button — the tall version cost more height than a folder needs. -->
  <li
    v-if="view === 'list'"
    :draggable="!editing"
    :class="[
      'group flex items-center gap-2 rounded-lg border bg-white px-3 py-2 transition',
      selected ? 'border-primary-500 bg-primary-50/40 ring-2 ring-primary-200' : '',
      isDropTarget ? 'border-primary-600 bg-primary-50 ring-2 ring-primary-200' : '',
      !selected && !isDropTarget ? 'border-gray-200' : '',
      isBeingDragged ? 'opacity-40' : 'hover:shadow-sm',
    ]"
    @dragstart="startDrag($event, 'folder', folder)"
    @dragend="endDrag"
    @dragover="onDragOver($event, folder.id, { descendantIds })"
    @dragleave="onDragLeave(folder.id)"
    @drop="handleDrop"
  >
    <button
      type="button"
      data-select-toggle
      :class="[
        'flex h-4 w-4 shrink-0 items-center justify-center rounded border transition',
        selected
          ? 'border-primary-600 bg-primary-600 text-white'
          : 'border-gray-300 text-transparent hover:border-primary-400',
        selecting || selected ? 'opacity-100' : 'opacity-0 group-hover:opacity-100 focus-visible:opacity-100',
      ]"
      :aria-label="selected ? `Deselect ${folder.name}` : `Select ${folder.name}`"
      :aria-pressed="selected"
      @click="onSelectClick"
    >
      <i class="fas fa-check text-[9px]" aria-hidden="true"></i>
    </button>

    <i
      class="fas fa-folder shrink-0"
      :style="{ color: folder.shared ? 'var(--color-primary-500)' : 'var(--color-warning-500)' }"
      aria-hidden="true"
    ></i>

    <div class="min-w-0 flex-1">
      <InlineName
        :name="folder.name"
        :editing="editing"
        :input-id="`rename-folder-${folder.id}`"
        label="Folder name"
        text-class="text-body-sm font-medium text-gray-800"
        @update:editing="emit('update:editing', $event)"
        @rename="emit('rename', { folder, name: $event })"
        @open="emit('open', folder.id)"
      />
    </div>

    <span class="hidden shrink-0 text-caption text-gray-400 sm:block">
      {{ folder.file_count }} {{ folder.file_count === 1 ? "file" : "files" }}
    </span>

    <i
      v-if="folder.shared"
      class="fas fa-users shrink-0 text-caption text-primary-600"
      title="Shared with family"
      aria-label="Shared with family"
    ></i>

    <button
      type="button"
      class="shrink-0 rounded-md p-2 text-gray-400 transition hover:bg-gray-100 hover:text-gray-700"
      :aria-label="`More actions for ${folder.name}`"
      @click.stop="emit('menu', $event)"
    >
      <i class="fas fa-ellipsis-vertical" aria-hidden="true"></i>
    </button>
  </li>

  <!-- Tile: same actions, laid out for a grid of cards alongside files. -->
  <li
    v-else
    :draggable="!editing"
    :class="[
      'group relative flex flex-col items-center gap-2 rounded-lg border bg-white p-3 text-center transition',
      selected ? 'border-primary-500 bg-primary-50/40 ring-2 ring-primary-200' : '',
      isDropTarget ? 'border-primary-600 bg-primary-50 ring-2 ring-primary-200' : '',
      !selected && !isDropTarget ? 'border-gray-200' : '',
      isBeingDragged ? 'opacity-40' : 'hover:shadow-md',
    ]"
    @dragstart="startDrag($event, 'folder', folder)"
    @dragend="endDrag"
    @dragover="onDragOver($event, folder.id, { descendantIds })"
    @dragleave="onDragLeave(folder.id)"
    @drop="handleDrop"
  >
    <button
      type="button"
      data-select-toggle
      :class="[
        'absolute left-2 top-2 z-10 flex h-5 w-5 items-center justify-center rounded border transition',
        selected
          ? 'border-primary-600 bg-primary-600 text-white'
          : 'border-white/80 bg-black/10 text-transparent hover:border-primary-400',
        selecting || selected ? 'opacity-100' : 'opacity-0 group-hover:opacity-100 focus-visible:opacity-100',
      ]"
      :aria-label="selected ? `Deselect ${folder.name}` : `Select ${folder.name}`"
      :aria-pressed="selected"
      @click="onSelectClick"
    >
      <i class="fas fa-check text-[10px]" aria-hidden="true"></i>
    </button>

    <button
      type="button"
      class="absolute right-1 top-1 z-10 rounded-md p-1.5 text-gray-400 opacity-0 transition hover:bg-gray-100 hover:text-gray-700 group-hover:opacity-100 focus-visible:opacity-100"
      :aria-label="`More actions for ${folder.name}`"
      @click.stop="emit('menu', $event)"
    >
      <i class="fas fa-ellipsis-vertical" aria-hidden="true"></i>
    </button>

    <button
      type="button"
      class="flex aspect-square w-full items-center justify-center rounded-lg bg-gray-50"
      @click="emit('open', folder.id)"
    >
      <i
        class="fas fa-folder text-4xl"
        :style="{ color: folder.shared ? 'var(--color-primary-500)' : 'var(--color-warning-500)' }"
        aria-hidden="true"
      ></i>
    </button>

    <div class="w-full min-w-0">
      <InlineName
        :name="folder.name"
        :editing="editing"
        :input-id="`rename-folder-grid-${folder.id}`"
        label="Folder name"
        text-class="text-body-sm font-medium text-gray-800 text-center"
        @update:editing="emit('update:editing', $event)"
        @rename="emit('rename', { folder, name: $event })"
        @open="emit('open', folder.id)"
      />
      <p class="text-caption text-gray-400">
        {{ folder.file_count }} {{ folder.file_count === 1 ? "file" : "files" }}
        <i v-if="folder.shared" class="fas fa-users ml-1 text-primary-600" title="Shared with family"></i>
      </p>
    </div>
  </li>
</template>
