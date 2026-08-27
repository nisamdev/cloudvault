<script setup>
import { ref } from "vue";
import PasswordGenerator from "@/components/records/PasswordGenerator.vue";
import { copyText } from "@/utils/clipboard";

/**
 * The generator on its own, for when you are signing up for something and just
 * need a password — no record, no saving, nothing kept.
 *
 * Deliberately keeps a short list of what it has made this visit. Sites reject
 * a password after you have already navigated away from the box you generated
 * it in, and having the last few still on screen saves starting again.
 */
const emit = defineEmits(["close"]);

const made = ref([]);
const copied = ref(-1);

function keep(password) {
  made.value = [password, ...made.value.filter((p) => p !== password)].slice(0, 5);
}

async function copy(password, index) {
  copied.value = (await copyText(password)) ? index : -1;
  setTimeout(() => (copied.value = -1), 2000);
}
</script>

<template>
  <div>
    <button
      type="button"
      class="mb-4 text-body-sm font-medium text-gray-500 transition hover:text-gray-700"
      @click="emit('close')"
    >
      <i class="fas fa-arrow-left mr-1" aria-hidden="true"></i>All tools
    </button>

    <div class="rounded-lg border border-gray-200 bg-white p-6">
      <h2 class="text-h3 font-semibold text-gray-800">Make a password</h2>
      <p class="mt-1 text-body-sm text-gray-500">
        Made in this browser and never sent anywhere. Copy it, or save it on a record from the
        register.
      </p>

      <div class="mt-5 max-w-xl">
        <PasswordGenerator use-label="Keep it" :dismissible="false" @use="keep" />
      </div>

      <section v-if="made.length" class="mt-6 max-w-xl">
        <h3 class="mb-2 text-caption uppercase tracking-wider text-gray-500">
          Kept while this page is open
        </h3>
        <ul class="divide-y divide-gray-100 rounded-base border border-gray-200">
          <li
            v-for="(password, index) in made"
            :key="password"
            class="flex items-center gap-3 px-3 py-2"
          >
            <code class="min-w-0 flex-1 break-all font-mono text-body-sm text-gray-800">
              {{ password }}
            </code>
            <button
              type="button"
              class="shrink-0 rounded-md p-1.5 text-gray-400 transition hover:bg-gray-100 hover:text-gray-700"
              :aria-label="`Copy password ${index + 1}`"
              @click="copy(password, index)"
            >
              <i
                :class="['fas', copied === index ? 'fa-check text-success-600' : 'fa-copy']"
                aria-hidden="true"
              ></i>
            </button>
          </li>
        </ul>
        <p class="mt-2 text-caption text-gray-500">
          These are gone when you leave the page. Nothing here has been saved.
        </p>
      </section>
    </div>
  </div>
</template>
