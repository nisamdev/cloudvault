<script setup>
import { onMounted, ref } from "vue";
import api from "@/api/client";
import { useLibraryStore } from "@/stores/library";

const props = defineProps({
  folderId: { type: [Number, String], default: null },
  visibility: { type: String, default: "private" },
});
const emit = defineEmits(["close"]);

const library = useLibraryStore();

const session = ref(null);
const loading = ref(true);
const error = ref("");
const copied = ref(false);
const closeButton = ref(null);

async function createSession() {
  loading.value = true;
  error.value = "";

  try {
    const { data } = await api.post("/scans", {
      folder_id: props.folderId || undefined,
      visibility: props.visibility,
    });
    session.value = data;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}

async function copyLink() {
  try {
    await navigator.clipboard.writeText(session.value.url);
    copied.value = true;
    setTimeout(() => (copied.value = false), 2000);
  } catch {
    error.value = "Couldn't copy — select the link and copy it manually.";
  }
}

function onKeydown(event) {
  if (event.key === "Escape") emit("close");
}

onMounted(() => {
  createSession();
  document.addEventListener("keydown", onKeydown);
  closeButton.value?.focus();
});
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-gray-900/50 p-4"
    @click.self="emit('close')"
  >
    <div
      class="w-full max-w-md rounded-xl bg-white shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-labelledby="scan-title"
    >
      <header class="flex items-start justify-between border-b border-gray-200 p-6">
        <div>
          <h2 id="scan-title" class="text-h3 font-semibold text-gray-800">Scan with your phone</h2>
          <p class="mt-1 text-body-sm text-gray-500">
            Point your camera at the code — no app needed.
          </p>
        </div>
        <button
          ref="closeButton"
          type="button"
          class="rounded-md p-2 text-gray-400 hover:bg-gray-100 hover:text-gray-600"
          aria-label="Close"
          @click="emit('close')"
        >
          <i class="fas fa-xmark" aria-hidden="true"></i>
        </button>
      </header>

      <div class="p-6 text-center">
        <p v-if="loading" class="py-10 text-body text-gray-500">
          <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Creating a link…
        </p>

        <p v-else-if="error" role="alert" class="rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
          {{ error }}
        </p>

        <template v-else>
          <!-- Rendered server-side as SVG, so it stays sharp and needs no JS lib -->
          <div class="mx-auto w-56" v-html="session.qr_svg"></div>

          <p class="mt-4 text-body-sm text-gray-600">
            Saves to <strong>{{ library.currentFolder?.name ?? "Top level" }}</strong>
            <span v-if="visibility === 'family'"> · shared with family</span>
          </p>
          <p class="mt-1 text-caption text-gray-400">
            Link expires in {{ session.expires_in_minutes }} minutes
          </p>

          <div class="mt-4 flex gap-2">
            <label for="scan-url" class="sr-only">Scanning link</label>
            <input
              id="scan-url"
              :value="session.url"
              readonly
              class="w-full rounded-base border border-gray-300 px-3 py-2 text-caption text-gray-600"
              @focus="$event.target.select()"
            />
            <button
              type="button"
              class="shrink-0 rounded-base bg-primary-600 px-4 py-2 text-body-sm font-semibold text-white"
              @click="copyLink"
            >
              <span aria-live="polite">{{ copied ? "Copied" : "Copy" }}</span>
            </button>
          </div>

          <p class="mt-4 text-caption text-gray-500">
            Anyone with this link can upload to your vault until it expires. It cannot read,
            download or delete anything.
          </p>
        </template>
      </div>
    </div>
  </div>
</template>
