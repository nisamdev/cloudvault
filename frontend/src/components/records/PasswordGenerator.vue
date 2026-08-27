<script setup>
import { computed, onMounted, ref, watch } from "vue";
import { DEFAULTS, describe, generate } from "@/utils/passwordGenerator";
import { copyText } from "@/utils/clipboard";

/**
 * Makes a password, in the browser.
 *
 * Nothing here reaches the server. A password you looked at and rejected should
 * never have existed anywhere but on this screen, so the whole thing is local
 * until you press Use it.
 */
const emit = defineEmits(["use", "close"]);

const mode = ref("random");
const options = ref({ ...DEFAULTS });
const value = ref("");
const copied = ref(false);
const error = ref("");

const strength = computed(() => describe(mode.value, options.value));

const toneClass = computed(
  () =>
    ({
      bad: "text-error-600",
      fair: "text-warning-600",
      good: "text-success-700",
      strong: "text-success-700",
    })[strength.value.tone] ?? "text-gray-600",
);

function make() {
  error.value = "";
  try {
    value.value = generate(mode.value, options.value);
  } catch (e) {
    value.value = "";
    error.value = e.message;
  }
}

onMounted(make);
watch([mode, options], make, { deep: true });

async function copy() {
  copied.value = await copyText(value.value);
  setTimeout(() => (copied.value = false), 2000);
}
</script>

<template>
  <div
    class="rounded-base border border-gray-200 bg-gray-50 p-3"
    role="group"
    aria-label="Password generator"
  >
    <!-- What it made -->
    <div class="flex items-start gap-2">
      <p
        class="min-w-0 flex-1 break-all rounded-base border border-gray-300 bg-white px-3 py-2 font-mono text-body-sm text-gray-800"
        aria-live="polite"
      >
        {{ value || "—" }}
      </p>
      <button
        type="button"
        class="rounded-base border border-gray-300 bg-white p-2 text-gray-500 transition hover:text-gray-800"
        aria-label="Make another"
        @click="make"
      >
        <i class="fas fa-rotate" aria-hidden="true"></i>
      </button>
      <button
        type="button"
        class="rounded-base border border-gray-300 bg-white p-2 text-gray-500 transition hover:text-gray-800"
        :aria-label="copied ? 'Copied' : 'Copy'"
        @click="copy"
      >
        <i :class="['fas', copied ? 'fa-check text-success-600' : 'fa-copy']" aria-hidden="true"></i>
      </button>
    </div>

    <p v-if="error" role="alert" class="mt-2 text-caption text-error-600">{{ error }}</p>

    <!-- How long it would take to guess. A number beats a coloured bar. -->
    <p v-else class="mt-2 text-caption text-gray-600">
      Guessing this would take <span :class="['font-medium', toneClass]">{{ strength.label }}</span>
      <span class="text-gray-400"> · {{ strength.bits }} bits</span>
    </p>

    <!-- Which kind -->
    <div class="mt-3 flex gap-1" role="tablist">
      <button
        v-for="option in [
          { value: 'random', label: 'Random' },
          { value: 'passphrase', label: 'Words' },
        ]"
        :key="option.value"
        type="button"
        role="tab"
        :aria-selected="mode === option.value"
        :class="[
          'rounded-base px-3 py-1 text-body-sm font-medium transition',
          mode === option.value
            ? 'bg-primary-600 text-white'
            : 'border border-gray-300 bg-white text-gray-600 hover:bg-gray-50',
        ]"
        @click="mode = option.value"
      >
        {{ option.label }}
      </button>
    </div>

    <!-- Random -->
    <div v-if="mode === 'random'" class="mt-3 space-y-2">
      <label class="flex items-center gap-3 text-body-sm text-gray-700">
        <span class="w-16 shrink-0">Length</span>
        <input
          v-model.number="options.length"
          type="range"
          min="8"
          max="64"
          class="flex-1 accent-primary-600"
        />
        <span class="w-8 shrink-0 text-right tabular-nums text-gray-500">{{ options.length }}</span>
      </label>

      <div class="flex flex-wrap gap-x-4 gap-y-1">
        <label
          v-for="cls in [
            { key: 'upper', label: 'A-Z' },
            { key: 'lower', label: 'a-z' },
            { key: 'digits', label: '0-9' },
            { key: 'symbols', label: '!@#' },
          ]"
          :key="cls.key"
          class="flex items-center gap-1.5 text-body-sm text-gray-700"
        >
          <input v-model="options[cls.key]" type="checkbox" class="accent-primary-600" />
          <span class="font-mono">{{ cls.label }}</span>
        </label>
      </div>

      <label class="flex items-center gap-1.5 text-body-sm text-gray-700">
        <input v-model="options.avoidAmbiguous" type="checkbox" class="accent-primary-600" />
        <span>Leave out look-alikes <span class="font-mono text-gray-400">l 1 I O 0</span></span>
      </label>
    </div>

    <!-- Passphrase -->
    <div v-else class="mt-3 space-y-2">
      <label class="flex items-center gap-3 text-body-sm text-gray-700">
        <span class="w-16 shrink-0">Words</span>
        <input
          v-model.number="options.words"
          type="range"
          min="3"
          max="9"
          class="flex-1 accent-primary-600"
        />
        <span class="w-8 shrink-0 text-right tabular-nums text-gray-500">{{ options.words }}</span>
      </label>

      <div class="flex flex-wrap items-center gap-x-4 gap-y-1">
        <label class="flex items-center gap-1.5 text-body-sm text-gray-700">
          <span>Joined by</span>
          <select
            v-model="options.separator"
            class="rounded-base border border-gray-300 bg-white px-2 py-1 font-mono text-body-sm"
          >
            <option value="-">-</option>
            <option value=".">.</option>
            <option value="_">_</option>
            <option value=" ">space</option>
          </select>
        </label>
        <label class="flex items-center gap-1.5 text-body-sm text-gray-700">
          <input v-model="options.capitalise" type="checkbox" class="accent-primary-600" />
          <span>Capitals</span>
        </label>
        <label class="flex items-center gap-1.5 text-body-sm text-gray-700">
          <input v-model="options.addNumber" type="checkbox" class="accent-primary-600" />
          <span>A number</span>
        </label>
      </div>
    </div>

    <div class="mt-3 flex gap-2">
      <button
        type="button"
        :disabled="!value"
        class="rounded-base bg-primary-600 px-4 py-1.5 text-body-sm font-medium text-white transition hover:bg-primary-700 disabled:opacity-50"
        @click="emit('use', value)"
      >
        Use it
      </button>
      <button
        type="button"
        class="rounded-base border border-gray-300 bg-white px-4 py-1.5 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
        @click="emit('close')"
      >
        Cancel
      </button>
    </div>
  </div>
</template>
