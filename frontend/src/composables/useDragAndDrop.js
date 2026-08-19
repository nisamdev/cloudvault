import { ref } from "vue";

/**
 * Drag-and-drop for moving files and folders into folders.
 *
 * Shared module-level state rather than per-component: the drag starts in the
 * listing and often ends in the sidebar tree, so both sides must agree on what
 * is being dragged. dataTransfer alone is not enough — its payload is
 * unreadable during dragover, which is exactly when we need to decide whether a
 * drop is allowed.
 */
const dragging = ref(null); // { type: "file" | "folder", id, name }
const dropTargetId = ref(null); // folder id currently hovered, or "root"

export function useDragAndDrop() {
  function startDrag(event, type, item) {
    dragging.value = { type, id: item.id, name: item.name };

    event.dataTransfer.effectAllowed = "move";
    // Some browsers refuse to start a drag without any payload set.
    event.dataTransfer.setData("text/plain", `${type}:${item.id}`);
  }

  function endDrag() {
    dragging.value = null;
    dropTargetId.value = null;
  }

  /**
   * Can the current drag land on this folder?
   * A folder cannot be dropped into itself; the caller supplies descendant ids
   * to prevent dropping a folder into its own subtree.
   */
  function canDropOn(folderId, { descendantIds = [] } = {}) {
    if (!dragging.value) return false;

    if (dragging.value.type === "folder") {
      if (dragging.value.id === folderId) return false;
      if (descendantIds.includes(folderId)) return false;
    }

    return true;
  }

  function onDragOver(event, folderId, options) {
    if (!canDropOn(folderId, options)) return;

    // preventDefault is what marks this element as a valid drop target.
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
    dropTargetId.value = folderId;
  }

  function onDragLeave(folderId) {
    if (dropTargetId.value === folderId) dropTargetId.value = null;
  }

  return {
    dragging,
    dropTargetId,
    startDrag,
    endDrag,
    canDropOn,
    onDragOver,
    onDragLeave,
  };
}
