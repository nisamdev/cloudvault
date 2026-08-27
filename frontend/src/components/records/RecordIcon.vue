<script setup>
import { computed, ref, watch } from "vue";
import { faviconUrl, initialsBackground, recordInitials, siteDomain } from "@/utils/recordIcon";

const props = defineProps({
  title: { type: String, default: "" },
  website: { type: String, default: "" },
  /** Font Awesome icon when there is no title to derive initials from. */
  typeIcon: { type: String, default: "fa-clipboard" },
  size: {
    type: String,
    default: "md",
    validator: (v) => ["sm", "md", "lg"].includes(v),
  },
});

const faviconFailed = ref(false);

const domain = computed(() => siteDomain(props.website));
const iconSrc = computed(() => (domain.value ? faviconUrl(domain.value) : null));
const showFavicon = computed(() => iconSrc.value && !faviconFailed.value);
const initials = computed(() => recordInitials(props.title));
const tileStyle = computed(() => ({
  backgroundColor: initialsBackground(props.title),
}));

const boxClass = computed(() => {
  if (props.size === "sm") return "h-8 w-8 text-caption";
  if (props.size === "lg") return "h-12 w-12 text-body";
  return "h-10 w-10 text-body-sm";
});

watch(
  () => props.website,
  () => {
    faviconFailed.value = false;
  },
);
</script>

<template>
  <span
    :class="['inline-flex shrink-0 items-center justify-center overflow-hidden rounded-base', boxClass]"
    aria-hidden="true"
  >
    <img
      v-if="showFavicon"
      :src="iconSrc"
      alt=""
      class="h-full w-full bg-white object-contain p-1"
      @error="faviconFailed = true"
    />
    <span
      v-else-if="title.trim()"
      class="flex h-full w-full items-center justify-center font-semibold uppercase text-white"
      :style="tileStyle"
    >
      {{ initials }}
    </span>
    <i v-else :class="['fas text-gray-400', typeIcon]" aria-hidden="true"></i>
  </span>
</template>
