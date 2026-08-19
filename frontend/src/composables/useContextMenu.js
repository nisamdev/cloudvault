import { ref } from "vue";

/**
 * One context menu for the whole screen.
 *
 * Module-level state on purpose: right-clicking a second item while a menu is
 * open must move that menu, not open a second one.
 */
const visible = ref(false);
const position = ref({ x: 0, y: 0 });
const items = ref([]);
const title = ref("");

export function useContextMenu() {
  /**
   * @param event  the contextmenu event (also fired by the keyboard menu key)
   * @param menu   { title, items: [{ label, icon, action, danger, divider }] }
   */
  function open(event, menu) {
    event.preventDefault();
    event.stopPropagation();

    title.value = menu.title ?? "";
    items.value = menu.items.filter(Boolean);
    position.value = { x: event.clientX, y: event.clientY };
    visible.value = true;
  }

  function close() {
    visible.value = false;
    items.value = [];
  }

  return { visible, position, items, title, open, close };
}
