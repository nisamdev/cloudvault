<script setup>
import { nextTick, ref, watch } from "vue";

/**
 * A name that turns into a text field in place.
 *
 * Renaming in a dialog costs a modal, a round trip of attention and a lost
 * sense of which row you were on. The name is already on screen; this lets it
 * be typed over.
 */
const props = defineProps({
  name: { type: String, required: true },
  editing: { type: Boolean, default: false },
  /** Announced to screen readers when the field appears. */
  label: { type: String, default: "Name" },
  inputId: { type: String, required: true },
  /**
   * Selects the stem and leaves the extension alone, the way a file manager
   * does — ".pdf" is almost never the part being changed, and retyping it is
   * how a file ends up called "Passport.pdf.pdf".
   */
  keepExtension: { type: Boolean, default: false },
  /** Styling for the resting state, so rows can keep their own typography. */
  textClass: { type: String, default: "text-body font-medium text-gray-800" },
});

const emit = defineEmits(["update:editing", "rename", "open"]);

const draft = ref(props.name);
const input = ref(null);

watch(
  () => props.editing,
  async (editing) => {
    if (!editing) return;

    draft.value = props.name;
    await nextTick();
    input.value?.focus();
    selectStem();
  },
);

// A rename from elsewhere (the API answering, another tab) should show.
watch(
  () => props.name,
  (name) => {
    if (!props.editing) draft.value = name;
  },
);

function selectStem() {
  const field = input.value;
  if (!field) return;

  const dot = props.keepExtension ? props.name.lastIndexOf(".") : -1;
  field.setSelectionRange(0, dot > 0 ? dot : props.name.length);
}

function submit() {
  const name = draft.value.trim();
  emit("update:editing", false);

  if (name && name !== props.name) emit("rename", name);
  else draft.value = props.name;
}

function cancel() {
  draft.value = props.name;
  emit("update:editing", false);
}
</script>

<template>
  <!-- Blur commits rather than discards: clicking away from a field you have
       typed into means you are done with it, not that you changed your mind.
       Escape is the way back out. -->
  <form v-if="editing" @submit.prevent="submit">
    <label :for="inputId" class="sr-only">{{ label }}</label>
    <input
      :id="inputId"
      ref="input"
      v-model="draft"
      type="text"
      class="w-full rounded-base border border-primary-400 px-2 py-1 text-body outline-none focus:ring-2 focus:ring-primary-500"
      @blur="submit"
      @keydown.esc.prevent="cancel"
      @click.stop
      @dragstart.stop.prevent
    />
  </form>

  <button
    v-else
    type="button"
    :class="['block w-full truncate text-left hover:text-primary-600', textClass]"
    @click="emit('open')"
  >
    {{ name }}
  </button>
</template>
