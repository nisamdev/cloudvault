<script setup>
import { computed, onMounted, ref } from "vue";
import api from "@/api/client";

/**
 * Whose record this is.
 *
 * The list is the Person records in the vault, not the family's logins: a
 * child holds a passport years before they hold an account, and the register
 * should be able to say so. Optional throughout — a boiler contract belongs to
 * the house, not to anybody.
 */
const props = defineProps({
  modelValue: { type: [Number, String], default: null },
  /** Never offer a record itself as its own holder. */
  excludeId: { type: [Number, String], default: null },
});
const emit = defineEmits(["update:modelValue"]);

const people = ref([]);
const loading = ref(true);

const options = computed(() =>
  people.value.filter((person) => String(person.id) !== String(props.excludeId)),
);

const selected = computed({
  get: () => (props.modelValue == null ? "" : String(props.modelValue)),
  set: (value) => emit("update:modelValue", value === "" ? null : Number(value)),
});

onMounted(async () => {
  try {
    const { data } = await api.get("/records");
    people.value = data.records
      .filter((record) => record.record_type === "person")
      .map((record) => ({ id: record.id, name: record.title }))
      .sort((a, b) => a.name.localeCompare(b.name));
  } catch {
    // Without the list the field simply is not offered, which is no worse
    // than the way it was before there was one.
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div v-if="loading || options.length">
    <label for="record-holder" class="mb-2 block text-caption uppercase tracking-wider text-gray-500">
      Whose is it
    </label>
    <select
      id="record-holder"
      v-model="selected"
      :disabled="loading"
      class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500 disabled:opacity-60"
    >
      <option value="">Nobody in particular</option>
      <option v-for="person in options" :key="person.id" :value="String(person.id)">
        {{ person.name }}
      </option>
    </select>
    <p class="mt-1 text-caption text-gray-500">
      Filed under this person, and findable by their name.
    </p>
  </div>
</template>
