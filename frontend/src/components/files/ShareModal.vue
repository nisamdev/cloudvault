<script setup>
import { nextTick, onMounted, onBeforeUnmount, ref } from "vue";
import api from "@/api/client";
import { useAuthStore } from "@/stores/auth";
import { useFilesStore } from "@/stores/files";
import { formatFileSize } from "@/utils/formatting";

const props = defineProps({
  file: { type: Object, required: true },
});
const emit = defineEmits(["close"]);

const auth = useAuthStore();
const filesStore = useFilesStore();

// Family sharing is a property of the file itself, separate from public links:
// one controls who inside the family can see it, the other hands access to
// anyone holding a URL.
const visibility = ref(props.file.visibility);
const savingVisibility = ref(false);

async function setVisibility(next) {
  if (next === visibility.value || savingVisibility.value) return;

  savingVisibility.value = true;
  error.value = "";
  const previous = visibility.value;
  visibility.value = next;

  try {
    const { data } = await api.patch(`/files/${props.file.id}`, { visibility: next });
    // Keep the list behind the modal in step (the Family badge, permissions).
    const index = filesStore.items.findIndex((f) => f.id === data.file.id);
    if (index >= 0) filesStore.items.splice(index, 1, data.file);
  } catch (e) {
    visibility.value = previous;
    error.value = e.userMessage;
  } finally {
    savingVisibility.value = false;
  }
}

const expiresIn = ref("7d");
const usePassword = ref(false);
const password = ref("");
const creating = ref(false);
const error = ref("");
const shareUrl = ref("");
const copied = ref(false);
const existingShares = ref([]);

const dialog = ref(null);
const closeButton = ref(null);
let previouslyFocused = null;

const EXPIRY_OPTIONS = [
  { value: "1h", label: "1 hour" },
  { value: "24h", label: "24 hours" },
  { value: "7d", label: "7 days" },
  { value: "30d", label: "30 days" },
  { value: "never", label: "Never" },
];

onMounted(async () => {
  // ACCESSIBILITY.md §Focus management: remember where focus came from, move it
  // into the dialog, and restore it on close.
  previouslyFocused = document.activeElement;
  await nextTick();
  closeButton.value?.focus();

  document.addEventListener("keydown", onKeydown);
  loadExisting();
});

onBeforeUnmount(() => {
  document.removeEventListener("keydown", onKeydown);
  previouslyFocused?.focus?.();
});

function onKeydown(event) {
  if (event.key === "Escape") {
    emit("close");
    return;
  }

  if (event.key !== "Tab") return;

  // Focus trap: keep Tab inside the dialog.
  const focusable = dialog.value?.querySelectorAll(
    'a[href], button:not([disabled]), input:not([disabled]), select, textarea, [tabindex]:not([tabindex="-1"])',
  );
  if (!focusable?.length) return;

  const first = focusable[0];
  const last = focusable[focusable.length - 1];

  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
}

async function loadExisting() {
  try {
    const { data } = await api.get(`/files/${props.file.id}/shares`);
    existingShares.value = data.shares;
  } catch {
    // Listing is a convenience; failing to load it must not block sharing.
  }
}

async function createLink() {
  creating.value = true;
  error.value = "";

  try {
    const { data } = await api.post(`/files/${props.file.id}/shares`, {
      expires_in: expiresIn.value,
      password: usePassword.value ? password.value : undefined,
    });

    // The URL is returned once and never again — show it immediately.
    shareUrl.value = data.share.url;
    loadExisting();
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    creating.value = false;
  }
}

async function copyLink() {
  try {
    await navigator.clipboard.writeText(shareUrl.value);
    copied.value = true;
    setTimeout(() => (copied.value = false), 2000);
  } catch {
    error.value = "Couldn't copy automatically — select the link and copy it.";
  }
}

async function revoke(share) {
  await api.delete(`/shares/${share.id}`);
  existingShares.value = existingShares.value.filter((s) => s.id !== share.id);
  if (existingShares.value.length === 0) shareUrl.value = "";
}
</script>

<template>
  <div
    class="fixed inset-0 z-40 flex items-center justify-center bg-gray-900/50 p-4"
    @click.self="emit('close')"
  >
    <div
      ref="dialog"
      class="w-full max-w-lg rounded-xl bg-white shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-labelledby="share-modal-title"
    >
      <header class="flex items-start justify-between border-b border-gray-200 p-6">
        <div class="min-w-0">
          <h2 id="share-modal-title" class="text-h3 font-semibold text-gray-800">Share file</h2>
          <p class="mt-1 truncate text-body-sm text-gray-500">
            {{ file.name }} · {{ formatFileSize(file.size) }}
          </p>
        </div>
        <button
          ref="closeButton"
          type="button"
          class="rounded-md p-2 text-gray-400 transition hover:bg-gray-100 hover:text-gray-600"
          aria-label="Close share dialog"
          @click="emit('close')"
        >
          <i class="fas fa-xmark" aria-hidden="true"></i>
        </button>
      </header>

      <div class="space-y-5 p-6">
        <p
          v-if="error"
          role="alert"
          class="rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
        >
          {{ error }}
        </p>

        <!-- Family access -->
        <div v-if="auth.family">
          <h3 class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500">
            Who can see this file
          </h3>

          <div class="grid grid-cols-2 gap-2" role="radiogroup" aria-label="File visibility">
            <button
              type="button"
              role="radio"
              :aria-checked="visibility === 'private'"
              :disabled="savingVisibility"
              :class="[
                'rounded-base border p-3 text-left transition disabled:opacity-60',
                visibility === 'private'
                  ? 'border-primary-600 bg-primary-50'
                  : 'border-gray-300 hover:bg-gray-50',
              ]"
              @click="setVisibility('private')"
            >
              <span class="flex items-center gap-2 text-body-sm font-medium text-gray-800">
                <i class="fas fa-lock text-gray-500" aria-hidden="true"></i>Only me
              </span>
              <span class="mt-1 block text-caption text-gray-500">Nobody else can see it</span>
            </button>

            <button
              type="button"
              role="radio"
              :aria-checked="visibility === 'family'"
              :disabled="savingVisibility || !auth.canEdit"
              :class="[
                'rounded-base border p-3 text-left transition disabled:opacity-60',
                visibility === 'family'
                  ? 'border-primary-600 bg-primary-50'
                  : 'border-gray-300 hover:bg-gray-50',
              ]"
              @click="setVisibility('family')"
            >
              <span class="flex items-center gap-2 text-body-sm font-medium text-gray-800">
                <i class="fas fa-users text-primary-600" aria-hidden="true"></i>My family
              </span>
              <span class="mt-1 block text-caption text-gray-500">
                Everyone in {{ auth.family.name }}
              </span>
            </button>
          </div>

          <p v-if="savingVisibility" class="mt-2 text-caption text-gray-500" aria-live="polite">
            Saving…
          </p>
        </div>

        <div v-if="auth.family" class="border-t border-gray-200 pt-5">
          <h3 class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500">
            Public link
          </h3>
        </div>

        <!-- The generated link. Shown once; it cannot be retrieved later. -->
        <div v-if="shareUrl" class="rounded-base bg-success-50 p-4">
          <p class="mb-2 text-body-sm font-medium text-success-700">
            <i class="fas fa-check mr-1" aria-hidden="true"></i>
            Link created — copy it now, it won't be shown again.
          </p>
          <div class="flex gap-2">
            <label for="share-url" class="sr-only">Share link</label>
            <input
              id="share-url"
              :value="shareUrl"
              readonly
              class="w-full rounded-base border border-gray-300 bg-white px-3 py-2 text-body-sm text-gray-700"
              @focus="$event.target.select()"
            />
            <button
              type="button"
              class="shrink-0 rounded-base bg-primary-600 px-4 py-2 text-body-sm font-semibold text-white transition hover:bg-primary-700"
              @click="copyLink"
            >
              <span aria-live="polite">{{ copied ? "Copied" : "Copy" }}</span>
            </button>
          </div>
        </div>

        <form v-else class="space-y-4" novalidate @submit.prevent="createLink">
          <div>
            <label for="share-expiry" class="mb-2 block text-body-sm font-medium text-gray-700">
              Link expires
            </label>
            <select
              id="share-expiry"
              v-model="expiresIn"
              class="w-full rounded-base border border-gray-300 px-3 py-2 outline-none focus:ring-2 focus:ring-primary-500"
            >
              <option v-for="option in EXPIRY_OPTIONS" :key="option.value" :value="option.value">
                {{ option.label }}
              </option>
            </select>
          </div>

          <div>
            <label class="flex items-center gap-2 text-body-sm text-gray-700">
              <input
                v-model="usePassword"
                type="checkbox"
                class="rounded border-gray-300 text-primary-600 focus:ring-primary-500"
              />
              Require a password
            </label>

            <input
              v-if="usePassword"
              v-model="password"
              type="text"
              placeholder="Password for this link"
              autocomplete="off"
              aria-label="Share password"
              class="mt-2 w-full rounded-base border border-gray-300 px-3 py-2 outline-none focus:ring-2 focus:ring-primary-500"
            />
          </div>

          <button
            type="submit"
            :disabled="creating || (usePassword && !password)"
            class="w-full rounded-base gradient-main py-2 font-semibold text-white transition hover:opacity-95 disabled:cursor-not-allowed disabled:opacity-60"
          >
            <span v-if="creating">
              <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Creating link…
            </span>
            <span v-else>Create share link</span>
          </button>
        </form>

        <!-- Existing links -->
        <div v-if="existingShares.length" class="border-t border-gray-200 pt-4">
          <h3 class="mb-3 text-label font-medium uppercase tracking-wide text-gray-500">
            Active links
          </h3>
          <ul class="space-y-2">
            <li
              v-for="share in existingShares"
              :key="share.id"
              class="flex items-center justify-between gap-3 rounded-base border border-gray-200 p-3"
            >
              <div class="min-w-0 text-body-sm">
                <p class="text-gray-700">
                  <i
                    v-if="share.password_protected"
                    class="fas fa-lock mr-1 text-gray-400"
                    aria-label="Password protected"
                  ></i>
                  {{ share.download_count }}
                  {{ share.download_count === 1 ? "download" : "downloads" }}
                </p>
                <p class="text-caption text-gray-500">
                  {{ share.expires_at ? `Expires ${new Date(share.expires_at).toLocaleDateString()}` : "Never expires" }}
                </p>
              </div>
              <button
                type="button"
                class="shrink-0 rounded-base px-3 py-1 text-body-sm font-medium text-error-600 transition hover:bg-error-50"
                @click="revoke(share)"
              >
                Revoke
              </button>
            </li>
          </ul>
        </div>
      </div>
    </div>
  </div>
</template>
