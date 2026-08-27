<script setup>
import { computed, ref, watch } from "vue";
import { faviconUrl, initialsBackground, recordInitials, siteDomain } from "@/utils/recordIcon";
import { recordTypeAccent, recordTypeTint } from "@/utils/recordType";

const props = defineProps({
  title: { type: String, default: "" },
  website: { type: String, default: "" },
  /** Font Awesome icon for the kind of record this is. */
  typeIcon: { type: String, default: "fa-clipboard" },
  /** The record type, which colours the tile when the kind is drawn. */
  recordType: { type: String, default: "" },
  /**
   * What the tile shows when there is no favicon.
   *
   * "kind" draws the type's icon — a passport, a car, a house — which is what
   * makes a list of documents readable at a glance. "initials" draws letters,
   * which is right for a person and for a service that has a name rather than
   * a shape.
   */
  fallback: {
    type: String,
    default: "initials",
    validator: (v) => ["initials", "kind"].includes(v),
  },
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
const showKind = computed(() => props.fallback === "kind");
const tint = computed(() => recordTypeTint(props.recordType));
const accent = computed(() => recordTypeAccent(props.recordType));
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
    <!-- The kind, drawn. A shelf of passports and licences is read by shape
         long before it is read by name. -->
    <span
      v-else-if="showKind"
      class="flex h-full w-full items-center justify-center"
      :style="{ backgroundColor: tint, color: accent }"
    >
      <i :class="['fas', typeIcon]" aria-hidden="true"></i>
    </span>
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
