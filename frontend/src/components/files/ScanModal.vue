<script setup>
import { onBeforeUnmount, onMounted, ref } from "vue";
import api from "@/api/client";
import { useLibraryStore } from "@/stores/library";

const props = defineProps({
  folderId: { type: [Number, String], default: null },
  visibility: { type: String, default: "private" },
});
const emit = defineEmits(["close", "uploaded"]);

const library = useLibraryStore();

const session = ref(null);
const loading = ref(true);
const error = ref("");
const copied = ref(false);
const closeButton = ref(null);
const received = ref(null);
let poller = null;

async function createSession() {
  loading.value = true;
  error.value = "";

  try {
    const { data } = await api.post("/scans", {
      folder_id: props.folderId || undefined,
      visibility: props.visibility,
    });
    session.value = data;
    startPolling();
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}

/**
 * The phone and the desktop share no connection, so the desktop asks whether
 * anything arrived. Without this the QR code sits there after the phone has
 * finished and the new file never appears until a manual reload.
 */
function startPolling() {
  const token = session.value.url.split("/scan/").pop();

  poller = setInterval(async () => {
    try {
      const { data } = await api.get(`/scans/${token}/status`);

      if (data.receipt) {
        received.value = data.receipt;
        stopPolling();
        // Tell the list to refresh so the scan is actually visible behind us.
        emit("uploaded", data.receipt);
      } else if (data.expired) {
        stopPolling();
        error.value = "This link has expired. Close and start a new scan.";
      }
    } catch {
      // A blip should not kill the dialog; the next tick tries again.
    }
  }, 2500);
}

function stopPolling() {
  if (poller) clearInterval(poller);
  poller = null;
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

onBeforeUnmount(() => {
  stopPolling();
  document.removeEventListener("keydown", onKeydown);
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

        <!-- The phone finished: stop showing a code nobody needs any more.
             v-else-if keeps this in the loading/error chain; a bare v-if would
             render the QR branch before the session exists. -->
        <template v-else-if="received">
          <i class="fas fa-circle-check text-5xl text-success-500" aria-hidden="true"></i>
          <h3 class="mt-4 text-h3 font-semibold text-gray-800">Scan received</h3>
          <ul class="mt-3 space-y-1">
            <li v-for="file in received.files" :key="file.id" class="text-body text-gray-600">
              {{ file.name }}
            </li>
          </ul>

          <div class="mt-6 flex gap-3">
            <button
              type="button"
              class="flex-1 rounded-base border border-gray-300 py-2 font-medium text-gray-700 hover:bg-gray-50"
              @click="received = null; createSession()"
            >
              Scan another
            </button>
            <button
              type="button"
              class="flex-1 rounded-base gradient-main py-2 font-semibold text-white"
              @click="emit('close')"
            >
              Done
            </button>
          </div>
        </template>

        <template v-else>
          <!-- Rendered server-side as SVG, so it stays sharp and needs no JS lib -->
          <div class="mx-auto w-56" v-html="session.qr_svg"></div>

          <p class="mt-3 flex items-center justify-center gap-2 text-caption text-gray-400">
            <i class="fas fa-circle-notch fa-spin" aria-hidden="true"></i>
            Waiting for your phone…
          </p>

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
