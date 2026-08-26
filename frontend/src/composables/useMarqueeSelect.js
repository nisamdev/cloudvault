import { onBeforeUnmount, ref } from "vue";

/**
 * Click-and-drag rectangle selection over a grid of items.
 *
 * Each selectable element needs `data-marquee-id` (the item id). Movement past
 * a small threshold starts the marquee so a plain click still opens a photo.
 *
 * `onSelect(ids, { additive })` is called as the rectangle moves. The parent
 * should replace the selection with `ids` (or union with the pre-drag set when
 * additive).
 */
export function useMarqueeSelect({ onSelect, rootRef }) {
  const box = ref(null);
  const active = ref(false);

  let origin = null;
  let additive = false;
  let moved = false;
  let suppressClick = false;

  function clientToRoot(clientX, clientY) {
    const root = rootRef.value;
    if (!root) return { x: clientX, y: clientY };
    const rect = root.getBoundingClientRect();
    return {
      x: clientX - rect.left + root.scrollLeft,
      y: clientY - rect.top + root.scrollTop,
    };
  }

  function onPointerDown(event) {
    if (event.button !== 0) return;
    // Checkboxes and explicit controls keep their own behaviour.
    if (event.target.closest("[data-select-toggle], input, select, textarea, a")) return;
    // Don't fight the timeline scrubber.
    if (event.target.closest("[aria-label='Photo timeline']")) return;

    const root = rootRef.value;
    if (!root || !root.contains(event.target)) return;

    const point = clientToRoot(event.clientX, event.clientY);
    origin = point;
    additive = event.metaKey || event.ctrlKey;
    moved = false;
    active.value = true;

    window.addEventListener("pointermove", onPointerMove);
    window.addEventListener("pointerup", onPointerUp, { once: true });
  }

  function onPointerMove(event) {
    if (!origin) return;

    const point = clientToRoot(event.clientX, event.clientY);
    const dx = point.x - origin.x;
    const dy = point.y - origin.y;

    if (!moved && Math.hypot(dx, dy) < 6) return;
    moved = true;
    suppressClick = true;

    const x = Math.min(origin.x, point.x);
    const y = Math.min(origin.y, point.y);
    const w = Math.abs(dx);
    const h = Math.abs(dy);
    box.value = { x, y, w, h };

    hitTest(x, y, w, h);
  }

  function hitTest(x, y, w, h) {
    const root = rootRef.value;
    if (!root) return;

    const rootRect = root.getBoundingClientRect();
    const sel = {
      left: rootRect.left + x - root.scrollLeft,
      top: rootRect.top + y - root.scrollTop,
      right: rootRect.left + x - root.scrollLeft + w,
      bottom: rootRect.top + y - root.scrollTop + h,
    };

    const ids = [];
    for (const el of root.querySelectorAll("[data-marquee-id]")) {
      const r = el.getBoundingClientRect();
      const intersects =
        r.left < sel.right &&
        r.right > sel.left &&
        r.top < sel.bottom &&
        r.bottom > sel.top;
      if (intersects) ids.push(el.getAttribute("data-marquee-id"));
    }

    onSelect(ids, { additive });
  }

  function onPointerUp() {
    window.removeEventListener("pointermove", onPointerMove);
    origin = null;
    active.value = false;
    box.value = null;

    if (suppressClick) {
      // Swallow the click that fires after a drag so the photo does not open.
      window.addEventListener("click", swallowClick, true);
      setTimeout(() => window.removeEventListener("click", swallowClick, true), 0);
    }
    suppressClick = false;
    moved = false;
  }

  function swallowClick(event) {
    event.stopPropagation();
    event.preventDefault();
  }

  onBeforeUnmount(() => {
    window.removeEventListener("pointermove", onPointerMove);
  });

  return { box, active, onPointerDown };
}
