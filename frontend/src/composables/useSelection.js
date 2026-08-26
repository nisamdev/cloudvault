import { computed, ref } from "vue";

/**
 * Multi-select for lists and grids.
 *
 * Keys are "file:id" / "folder:id" so files and folders can share one set.
 * Shift-click selects a range against the last anchor; ctrl/cmd toggles.
 */
export function useSelection() {
  const selected = ref(new Set());
  const anchor = ref(null);

  const count = computed(() => selected.value.size);
  const hasSelection = computed(() => selected.value.size > 0);

  function key(type, id) {
    return `${type}:${id}`;
  }

  function isSelected(type, id) {
    return selected.value.has(key(type, id));
  }

  function clear() {
    selected.value = new Set();
    anchor.value = null;
  }

  function setOnly(type, id) {
    selected.value = new Set([key(type, id)]);
    anchor.value = key(type, id);
  }

  function toggle(type, id) {
    const next = new Set(selected.value);
    const k = key(type, id);
    if (next.has(k)) next.delete(k);
    else next.add(k);
    selected.value = next;
    anchor.value = k;
  }

  /**
   * @param {Array<{ type: string, id: string|number }>} ordered
   *   Visible items in display order, used for shift-range.
   */
  function onSelect(type, id, event, ordered = []) {
    const k = key(type, id);
    const additive = event.metaKey || event.ctrlKey;
    const range = event.shiftKey && anchor.value;

    if (range) {
      const keys = ordered.map((item) => key(item.type, item.id));
      const from = keys.indexOf(anchor.value);
      const to = keys.indexOf(k);
      if (from >= 0 && to >= 0) {
        const [start, end] = from < to ? [from, to] : [to, from];
        const next = additive ? new Set(selected.value) : new Set();
        for (let i = start; i <= end; i += 1) next.add(keys[i]);
        selected.value = next;
        return;
      }
    }

    if (additive) {
      toggle(type, id);
      return;
    }

    // Plain click on a checkbox: toggle this one without wiping the rest when
    // something is already selected — feels like a real multi-select.
    if (selected.value.size > 0 && event.target?.closest?.("[data-select-toggle]")) {
      toggle(type, id);
      return;
    }

    setOnly(type, id);
  }

  function selectAll(ordered) {
    selected.value = new Set(ordered.map((item) => key(item.type, item.id)));
    anchor.value = ordered.length ? key(ordered[0].type, ordered[0].id) : null;
  }

  /** Replace or union a batch of items (marquee / select-day). */
  function selectMany(items, { additive = false } = {}) {
    const keys = items.map((item) => key(item.type, item.id));
    const next = additive ? new Set(selected.value) : new Set();
    for (const k of keys) next.add(k);
    selected.value = next;
    if (keys.length) anchor.value = keys[keys.length - 1];
  }

  function selectedOf(type) {
    const prefix = `${type}:`;
    return [...selected.value]
      .filter((k) => k.startsWith(prefix))
      .map((k) => k.slice(prefix.length));
  }

  return {
    selected,
    count,
    hasSelection,
    isSelected,
    clear,
    setOnly,
    toggle,
    onSelect,
    selectAll,
    selectMany,
    selectedOf,
    key,
  };
}
