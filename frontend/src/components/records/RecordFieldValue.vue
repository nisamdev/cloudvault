<script setup>
import { computed } from "vue";
import { formatRecordDate } from "@/utils/recordDate";

/**
 * One value, rendered according to what it is for.
 *
 * Reference numbers, meter numbers and sort codes are set in monospace: they
 * are machine data, they get copied rather than read, and the shape of the
 * characters is what you check them by.
 */
const props = defineProps({
  field: { type: Object, required: true },
  value: { type: [String, Number], default: "" },
});

const text = computed(() => String(props.value ?? ""));

const isData = computed(() => ["reference", "number"].includes(props.field.kind));
const isDate = computed(() => ["date", "expiry"].includes(props.field.kind));

const href = computed(() => {
  if (props.field.kind === "email") return `mailto:${text.value}`;
  if (props.field.kind === "phone") return `tel:${text.value.replace(/\s/g, "")}`;
  if (props.field.kind === "url") {
    return /^https?:\/\//i.test(text.value) ? text.value : `https://${text.value}`;
  }
  return null;
});
</script>

<template>
  <a
    v-if="href"
    :href="href"
    :target="field.kind === 'url' ? '_blank' : undefined"
    rel="noopener noreferrer"
    class="break-words text-body text-primary-600 hover:underline"
  >
    {{ text }}
  </a>
  <p
    v-else-if="isData"
    class="break-all font-mono text-body text-gray-800"
  >
    {{ text }}
  </p>
  <p v-else-if="isDate" class="font-mono text-body text-gray-800">
    {{ formatRecordDate(text) }}
  </p>
  <p v-else class="whitespace-pre-line break-words text-body text-gray-800">{{ text }}</p>
</template>
