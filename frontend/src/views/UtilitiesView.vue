<script setup>
import { ref } from "vue";
import MergePdfTool from "@/components/utilities/MergePdfTool.vue";

/**
 * Tools that act on documents rather than store them.
 *
 * Each one opens in place rather than in a modal: these are tasks, not
 * decisions, and they need room to show what they are about to do.
 */
const TOOLS = [
  {
    key: "merge",
    name: "Merge PDFs",
    summary: "Join several documents into one, in the order you choose.",
    detail: "Both sides of a passport, or a scan that came out as separate files.",
    icon: "fa-object-group",
    tint: "bg-primary-50 text-primary-600",
    ready: true,
  },
  {
    key: "images-to-pdf",
    name: "Photos to PDF",
    summary: "Turn a set of photos into a single document.",
    detail: "For pages you photographed instead of scanning.",
    icon: "fa-file-image",
    tint: "bg-secondary-50 text-secondary-600",
  },
  {
    key: "pages",
    name: "Rearrange pages",
    summary: "Reorder, rotate or remove pages inside a PDF.",
    detail: "Fix a scan that came out upside down or back to front.",
    icon: "fa-arrows-rotate",
    tint: "bg-warning-50 text-warning-600",
  },
  {
    key: "split",
    name: "Split a PDF",
    summary: "Pull out a page range as its own document.",
    detail: "One statement out of a year of them.",
    icon: "fa-scissors",
    tint: "bg-info-50 text-info-700",
  },
  {
    key: "ocr",
    name: "Make a scan searchable",
    summary: "Read the text inside a scan so search can find it.",
    detail: "Find a passport by its number, not just its filename.",
    icon: "fa-magnifying-glass",
    tint: "bg-success-50 text-success-700",
  },
];

const open = ref(null);
</script>

<template>
  <section>
    <header class="mb-6">
      <h1 class="text-h2 font-bold text-gray-800">Tools</h1>
      <p class="mt-1 text-body-sm text-gray-500">
        Things to do with your documents, not just places to keep them
      </p>
    </header>

    <MergePdfTool v-if="open === 'merge'" @close="open = null" />

    <div v-else class="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
      <component
        :is="tool.ready ? 'button' : 'div'"
        v-for="tool in TOOLS"
        :key="tool.key"
        :type="tool.ready ? 'button' : undefined"
        :class="[
          'rounded-lg border border-gray-200 bg-white p-5 text-left transition',
          tool.ready ? 'hover:border-primary-300 hover:shadow-md' : 'opacity-60',
        ]"
        @click="tool.ready && (open = tool.key)"
      >
        <span :class="['inline-flex h-10 w-10 items-center justify-center rounded-lg', tool.tint]">
          <i :class="['fas', tool.icon]" aria-hidden="true"></i>
        </span>

        <h2 class="mt-3 text-body font-semibold text-gray-800">
          {{ tool.name }}
          <span v-if="!tool.ready" class="ml-1 text-caption font-normal text-gray-400">soon</span>
        </h2>
        <p class="mt-1 text-body-sm text-gray-600">{{ tool.summary }}</p>
        <p class="mt-1 text-caption text-gray-500">{{ tool.detail }}</p>
      </component>
    </div>
  </section>
</template>
