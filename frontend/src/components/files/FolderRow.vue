<script setup>
import { computed, nextTick, ref } from "vue";
import { useLibraryStore } from "@/stores/library";
import { useDragAndDrop } from "@/composables/useDragAndDrop";

const props = defineProps({
  folder: { type: Object, required: true },
});
const emit = defineEmits(["open", "drop", "rename", "delete", "download"]);

const library = useLibraryStore();
const { dragging, dropTargetId, startDrag, endDrag, onDragOver, onDragLeave } = useDragAndDrop();

const renaming = ref(false);
const draftName = ref(props.folder.name);
const nameInput = ref(null);

async function beginRename() {
  renaming.value = true;
  await nextTick();
  nameInput.value?.focus();
  nameInput.value?.select();
}

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

function submitRename() {
  const name = draftName.value.trim();
  renaming.value = false;
  if (name && name !== props.folder.name) emit("rename", { folder: props.folder, name });
  else draftName.value = props.folder.name;
}
</script>

<template>
  <li
    draggable="true"
    :class="[
      'flex items-center gap-4 rounded-lg border bg-white p-4 transition',
      isDropTarget ? 'border-primary-600 bg-primary-50 ring-2 ring-primary-200' : 'border-gray-200',
      isBeingDragged ? 'opacity-40' : 'hover:shadow-md',
    ]"
    @dragstart="startDrag($event, 'folder', folder)"
    @dragend="endDrag"
    @dragover="onDragOver($event, folder.id, { descendantIds })"
    @dragleave="onDragLeave(folder.id)"
    @drop="handleDrop"
  >
    <i
      class="fas fa-folder text-xl"
      :style="{ color: folder.shared ? 'var(--color-primary-500)' : 'var(--color-warning-500)' }"
      aria-hidden="true"
    ></i>

    <div class="min-w-0 flex-1">
      <form v-if="renaming" @submit.prevent="submitRename">
        <label :for="`rename-${folder.id}`" class="sr-only">Folder name</label>
        <input
          :id="`rename-${folder.id}`"
          ref="nameInput"
          v-model="draftName"
          type="text"
          class="w-full rounded-base border border-gray-300 px-2 py-1 text-body outline-none focus:ring-2 focus:ring-primary-500"
          @blur="submitRename"
          @keydown.esc="renaming = false; draftName = folder.name"
        />
      </form>

      <button
        v-else
        type="button"
        class="block w-full truncate text-left text-body font-medium text-gray-800 hover:text-primary-600"
        @click="emit('open', folder.id)"
      >
        {{ folder.name }}
      </button>

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
        @click="beginRename"
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
