<script setup>
import { computed } from "vue";
import { expiryState } from "@/utils/recordDate";

/**
 * How long this record has left.
 *
 * The one place in the register that uses semantic colour. Everything else is
 * ink and grey, so a permit running out is the only thing on the page that can
 * shout — which is the whole reason the register exists.
 */
const props = defineProps({
  field: { type: Object, required: true },
  value: { type: String, required: true },
  /** The date the term began, when the record knows it. */
  from: { type: String, default: null },
});

const state = computed(() => expiryState(props.value, props.from));

const tone = computed(
  () =>
    ({
      expired: {
        rule: "border-error-500",
        text: "text-error-600",
        bar: "bg-error-500",
        track: "bg-error-50",
      },
      urgent: {
        rule: "border-error-500",
        text: "text-error-600",
        bar: "bg-error-500",
        track: "bg-error-50",
      },
      soon: {
        rule: "border-warning-500",
        text: "text-warning-600",
        bar: "bg-warning-500",
        track: "bg-warning-50",
      },
      fine: {
        rule: "border-gray-200",
        text: "text-gray-600",
        bar: "bg-gray-300",
        track: "bg-gray-100",
      },
    })[state.value?.tone ?? "fine"],
);
</script>

<template>
  <div v-if="state" :class="['border-l-2 pl-4', tone.rule]">
    <p class="text-caption uppercase tracking-wider text-gray-500">{{ field.label }}</p>

    <p class="mt-1 flex flex-wrap items-baseline gap-x-3 gap-y-1">
      <span class="font-mono text-h4 text-gray-800">{{ state.formatted }}</span>
      <span :class="['text-body-sm font-medium', tone.text]">{{ state.label }}</span>
    </p>

    <!-- Only drawn when the term's start is known. A proportional bar with an
         invented denominator would be decoration pretending to be information. -->
    <div v-if="state.elapsed !== undefined" :class="['mt-2 h-1 w-full max-w-sm rounded-full', tone.track]">
      <div
        :class="['h-full rounded-full transition-all', tone.bar]"
        :style="{ width: `${Math.round(state.elapsed * 100)}%` }"
      ></div>
    </div>
  </div>
</template>
