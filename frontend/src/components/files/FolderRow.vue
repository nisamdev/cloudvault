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
});
const emit = defineEmits([
  "open", "drop", "rename", "delete", "download", "update:editing", "select",
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
  <li
    :draggable="!editing"
    :class="[
      'group flex items-center gap-3 rounded-lg border bg-white p-4 transition',
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
        'flex h-5 w-5 shrink-0 items-center justify-center rounded border transition',
        selected
          ? 'border-primary-600 bg-primary-600 text-white'
          : 'border-gray-300 text-transparent hover:border-primary-400',
        selecting || selected ? 'opacity-100' : 'opacity-0 group-hover:opacity-100 focus-visible:opacity-100',
      ]"
      :aria-label="selected ? `Deselect ${folder.name}` : `Select ${folder.name}`"
      :aria-pressed="selected"
      @click="onSelectClick"
    >
      <i class="fas fa-check text-[10px]" aria-hidden="true"></i>
    </button>

    <i
      class="fas fa-folder text-xl"
      :style="{ color: folder.shared ? 'var(--color-primary-500)' : 'var(--color-warning-500)' }"
      aria-hidden="true"
    ></i>

    <div class="min-w-0 flex-1">
      <InlineName
        :name="folder.name"
        :editing="editing"
        :input-id="`rename-folder-${folder.id}`"
        label="Folder name"
        @update:editing="emit('update:editing', $event)"
        @rename="emit('rename', { folder, name: $event })"
        @open="emit('open', folder.id)"
      />

      <p class="text-caption text-gray-500">
        {{ folder.file_count }} {{ folder.file_count === 1 ? "file" : "files" }}
        <span v-if="folder.shared"> · shared with family</span>
      </p>
    </div>

    <span
      v-if="folder.shared"
      class="rounded-full bg-primary-50 px-2 py-1 text-label font-medium text-primary-700"
    >
      <i class="fas fa-users mr-1" aria-hidden="true"></i>Family
    </span>

    <div class="flex items-center gap-1">
      <button
        type="button"
        class="rounded-md p-2 text-gray-500 transition hover:bg-gray-100 hover:text-gray-700"
        :aria-label="`Download ${folder.name} as ZIP`"
        @click="emit('download', folder)"
      >
        <i class="fas fa-file-zipper" aria-hidden="true"></i>
      </button>
      <button
        type="button"
        class="rounded-md p-2 text-gray-500 transition hover:bg-gray-100 hover:text-gray-700"
        :aria-label="`Rename ${folder.name}`"
        @click="emit('update:editing', true)"
      >
        <i class="fas fa-pen" aria-hidden="true"></i>
      </button>
      <button
        type="button"
        class="rounded-md p-2 text-gray-500 transition hover:bg-error-50 hover:text-error-600"
        :aria-label="`Delete ${folder.name}`"
        @click="emit('delete', folder)"
      >
        <i class="fas fa-trash" aria-hidden="true"></i>
      </button>
    </div>
  </li>
</template>
