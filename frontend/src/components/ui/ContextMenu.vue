<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { useContextMenu } from "@/composables/useContextMenu";

const { visible, position, items, title, close } = useContextMenu();

const menu = ref(null);
const activeIndex = ref(-1);
// Measured after render so the menu can flip near the viewport edges.
const size = ref({ width: 220, height: 0 });

let previouslyFocused = null;

// Only real entries are focusable; dividers are skipped by keyboard nav.
const selectableIndexes = computed(() =>
  items.value.map((item, index) => (item.divider ? null : index)).filter((i) => i !== null),
);

const style = computed(() => {
  const margin = 8;
  const { x, y } = position.value;
  const maxX = window.innerWidth - size.value.width - margin;
  const maxY = window.innerHeight - size.value.height - margin;

  return {
    left: `${Math.max(margin, Math.min(x, maxX))}px`,
    top: `${Math.max(margin, Math.min(y, maxY))}px`,
  };
});

watch(visible, async (isOpen) => {
  if (!isOpen) {
    previouslyFocused?.focus?.();
    activeIndex.value = -1;
    return;
  }

  previouslyFocused = document.activeElement;
  await nextTick();

  const rect = menu.value?.getBoundingClientRect();
  if (rect) size.value = { width: rect.width, height: rect.height };

  menu.value?.focus();
});

function run(item) {
  if (item.disabled || item.divider) return;
  close();
  item.action?.();
}

function move(delta) {
  const list = selectableIndexes.value;
  if (!list.length) return;

  const current = list.indexOf(activeIndex.value);
  const next = current === -1 ? (delta > 0 ? 0 : list.length - 1) : (current + delta + list.length) % list.length;
  activeIndex.value = list[next];
}

function onKeydown(event) {
  switch (event.key) {
    case "Escape":
      event.preventDefault();
      close();
      break;
    case "ArrowDown":
      event.preventDefault();
      move(1);
      break;
    case "ArrowUp":
      event.preventDefault();
      move(-1);
      break;
    case "Home":
      event.preventDefault();
      activeIndex.value = selectableIndexes.value[0];
      break;
    case "End":
      event.preventDefault();
      activeIndex.value = selectableIndexes.value.at(-1);
      break;
    case "Enter":
    case " ":
      event.preventDefault();
      if (activeIndex.value >= 0) run(items.value[activeIndex.value]);
      break;
    default:
      break;
  }
}

// A scroll or resize leaves the menu pointing at nothing, so dismiss it.
function dismiss() {
  if (visible.value) close();
}

onMounted(() => {
  window.addEventListener("scroll", dismiss, true);
  window.addEventListener("resize", dismiss);
});

onBeforeUnmount(() => {
  window.removeEventListener("scroll", dismiss, true);
  window.removeEventListener("resize", dismiss);
});
</script>

<template>
  <!-- Backdrop catches the click (and the next right-click) that dismisses the menu -->
  <div
    v-if="visible"
    class="fixed inset-0 z-50"
    @click="close"
    @contextmenu.prevent="close"
  >
    <div
      ref="menu"
      role="menu"
      tabindex="-1"
      :aria-label="title || 'Actions'"
      class="absolute min-w-52 rounded-lg border border-gray-200 bg-white py-1 shadow-xl outline-none"
      :style="style"
      @click.stop
      @keydown="onKeydown"
    >
      <p v-if="title" class="truncate px-3 py-1.5 text-caption font-medium text-gray-400">
        {{ title }}
      </p>

      <template v-for="(item, index) in items" :key="index">
        <hr v-if="item.divider" class="my-1 border-gray-200" role="separator" />

        <button
          v-else
          type="button"
          role="menuitem"
          :disabled="item.disabled"
          :class="[
            'flex w-full items-center gap-3 px-3 py-2 text-left text-body-sm transition',
            item.disabled
              ? 'cursor-not-allowed text-gray-300'
              : item.danger
                ? 'text-error-600 hover:bg-error-50'
                : 'text-gray-700 hover:bg-gray-100',
            activeIndex === index && !item.disabled
              ? item.danger
                ? 'bg-error-50'
                : 'bg-gray-100'
              : '',
          ]"
          @click="run(item)"
          @mouseenter="activeIndex = index"
        >
          <i :class="['fas', item.icon || 'fa-circle', 'w-4 text-center text-caption']" aria-hidden="true"></i>
          <span class="flex-1 truncate">{{ item.label }}</span>
          <span v-if="item.hint" class="text-caption text-gray-400">{{ item.hint }}</span>
        </button>
      </template>
    </div>
  </div>
</template>
