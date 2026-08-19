<script setup>
import { computed, ref } from "vue";
import { useLibraryStore } from "@/stores/library";
import { useDragAndDrop } from "@/composables/useDragAndDrop";

defineProps({
  nodes: { type: Array, required: true },
  depth: { type: Number, default: 0 },
});
const emit = defineEmits(["open", "drop", "menu"]);

const library = useLibraryStore();
const { dragging, dropTargetId, startDrag, endDrag, onDragOver, onDragLeave } = useDragAndDrop();

function descendantsOf(id) {
  return library.descendantIds(id);
}

function handleDrop(event, folderId) {
  event.preventDefault();
  const payload = dragging.value;
  endDrag();
  if (payload) emit("drop", { payload, targetFolderId: folderId });
}

// Collapsed state per folder id. Folders start expanded so the whole tree is
// visible on a small vault; the user can fold away what they don't need.
const collapsed = ref({});

function toggle(id) {
  collapsed.value[id] = !collapsed.value[id];
}
</script>

<template>
  <ul :class="depth === 0 ? 'space-y-0.5' : 'ml-3 space-y-0.5 border-l border-gray-200 pl-2'">
    <li v-for="node in nodes" :key="node.id">
      <div
        draggable="true"
        :class="[
          'group flex items-center gap-1 rounded-base px-2 py-1.5 text-body-sm transition',
          dropTargetId === node.id
            ? 'bg-primary-100 ring-2 ring-primary-400'
            : library.currentFolderId === node.id
              ? 'bg-primary-50 text-primary-700'
              : 'text-gray-600 hover:bg-gray-100',
          dragging?.type === 'folder' && dragging.id === node.id ? 'opacity-40' : '',
        ]"
        @dragstart.stop="startDrag($event, 'folder', node)"
        @dragend="endDrag"
        @dragover="onDragOver($event, node.id, { descendantIds: descendantsOf(node.id) })"
        @dragleave="onDragLeave(node.id)"
        @drop="handleDrop($event, node.id)"
        @contextmenu="emit('menu', $event, node)"
      >
        <button
          v-if="node.children.length"
          type="button"
          class="shrink-0 rounded p-0.5 text-gray-400 hover:text-gray-700"
          :aria-expanded="!collapsed[node.id]"
          :aria-label="`${collapsed[node.id] ? 'Expand' : 'Collapse'} ${node.name}`"
          @click.stop="toggle(node.id)"
        >
          <i
            :class="['fas', collapsed[node.id] ? 'fa-chevron-right' : 'fa-chevron-down', 'text-caption']"
            aria-hidden="true"
          ></i>
        </button>
        <!-- Keeps leaf folders aligned with folders that have a chevron -->
        <span v-else class="w-4 shrink-0" aria-hidden="true"></span>

        <button
          type="button"
          class="flex min-w-0 flex-1 items-center gap-2 text-left"
          @click="emit('open', node.id)"
        >
          <i
            :class="['fas', node.shared ? 'fa-folder-open' : 'fa-folder', 'shrink-0 text-caption']"
            :style="{ color: node.shared ? 'var(--color-primary-500)' : 'var(--color-gray-400)' }"
            aria-hidden="true"
          ></i>
          <span class="truncate">{{ node.name }}</span>
          <span v-if="node.file_count" class="shrink-0 text-caption text-gray-400">
            {{ node.file_count }}
          </span>
        </button>
      </div>

      <!-- Recursion renders the subtree. -->
      <FolderTree
        v-if="node.children.length && !collapsed[node.id]"
        :nodes="node.children"
        :depth="depth + 1"
        @open="emit('open', $event)"
        @drop="emit('drop', $event)"
        @menu="(e, n) => emit('menu', e, n)"
      />
    </li>
  </ul>
</template>
