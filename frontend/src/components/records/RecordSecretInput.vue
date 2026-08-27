<script setup>
import { ref } from "vue";

/**
 * One secret field on a create/edit form. Values never come back from the API —
 * leave blank to keep an existing password.
 */
defineProps({
  field: { type: Object, required: true },
  modelValue: { type: String, default: "" },
  saved: { type: Boolean, default: false },
});

const emit = defineEmits(["update:modelValue"]);

const visible = ref(false);
</script>

<template>
  <div>
    <label :for="`secret-${field.key}`" class="mb-1 block text-body-sm font-medium text-gray-700">
      {{ field.label }}
    </label>
    <textarea
      v-if="field.key.includes('answer')"
      :id="`secret-${field.key}`"
      :value="modelValue"
      rows="3"
      autocomplete="off"
      :placeholder="saved ? 'Saved — enter a new value to replace' : field.hint"
      class="w-full rounded-base border border-gray-300 px-3 py-2 font-mono text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
      @input="emit('update:modelValue', $event.target.value)"
    ></textarea>
    <div v-else class="relative">
      <input
        :id="`secret-${field.key}`"
        :value="modelValue"
        :type="visible ? 'text' : 'password'"
        autocomplete="new-password"
        :placeholder="saved ? 'Saved — enter a new value to replace' : field.hint"
        class="w-full rounded-base border border-gray-300 py-2 pl-3 pr-10 font-mono text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
        @input="emit('update:modelValue', $event.target.value)"
      />
      <button
        type="button"
        class="absolute right-2 top-1/2 -translate-y-1/2 rounded p-1 text-gray-400 hover:text-gray-700"
        :aria-label="visible ? 'Hide password' : 'Show password'"
        :aria-pressed="visible"
        @click="visible = !visible"
      >
        <i :class="['fas', visible ? 'fa-eye-slash' : 'fa-eye']" aria-hidden="true"></i>
      </button>
    </div>
    <p v-if="saved && !modelValue" class="mt-1 text-caption text-gray-500">
      A value is saved. Leave empty to keep it, or enter something new to replace it.
    </p>
  </div>
</template>
