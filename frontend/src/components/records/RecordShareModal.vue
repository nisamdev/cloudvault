<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from "vue";
import api from "@/api/client";

/**
 * A timed, read-only link to one record and its documents.
 *
 * Sharing with the family is a property of the record — who inside the house
 * can see it. This is the other thing entirely: a URL for somebody outside it,
 * good until a date you pick, and revocable before then. The landlord who
 * wants to see a passport does not need an account, and should not keep the
 * access afterwards.
 */
const props = defineProps({
  record: { type: Object, required: true },
});
const emit = defineEmits(["close"]);

const EXPIRY_OPTIONS = [
  { value: "1h", label: "1 hour" },
  { value: "24h", label: "24 hours" },
  { value: "7d", label: "7 days" },
  { value: "30d", label: "30 days" },
];

const expiresIn = ref("7d");
const usePassword = ref(false);
const password = ref("");
const creating = ref(false);
const error = ref("");
const shareUrl = ref("");
const copied = ref(false);
const existing = ref([]);

const dialog = ref(null);
const closeButton = ref(null);
let previouslyFocused = null;

const documentCount = computed(() => props.record.attachments?.length ?? 0);

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
    const { data } = await api.get(`/records/${props.record.id}/shares`);
    existing.value = data.shares;
  } catch {
    // Listing is a convenience; failing to load it must not block sharing.
  }
}

async function createLink() {
  creating.value = true;
  error.value = "";

  try {
    const { data } = await api.post(`/records/${props.record.id}/shares`, {
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
  existing.value = existing.value.filter((s) => s.id !== share.id);
  if (!existing.value.length) shareUrl.value = "";
}

function expiryLabel(share) {
  return share.expires_at
    ? `Expires ${new Date(share.expires_at).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" })}`
    : "Never expires";
}
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-gray-900/50 p-4"
    @click.self="emit('close')"
  >
    <div
      ref="dialog"
      class="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-xl bg-white shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-labelledby="record-share-title"
    >
      <header class="flex items-start justify-between border-b border-gray-200 p-6">
        <div class="min-w-0">
          <h2 id="record-share-title" class="text-h3 font-semibold text-gray-800">
            Share a temporary link
          </h2>
          <p class="mt-1 truncate text-body-sm text-gray-500">{{ record.title }}</p>
        </div>
        <button
          ref="closeButton"
          type="button"
          class="ml-3 shrink-0 rounded-md p-2 text-gray-400 hover:bg-gray-100 hover:text-gray-600"
          aria-label="Close"
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

        <!-- The link, once it exists. Shown here and nowhere else, ever. -->
        <div v-if="shareUrl" class="rounded-base border border-success-100 bg-success-50 p-4">
          <p class="mb-2 text-body-sm font-medium text-success-700">
            <i class="fas fa-circle-check mr-1.5" aria-hidden="true"></i>
            Link ready. Copy it now — it isn't shown again.
          </p>
          <div class="flex gap-2">
            <label for="record-share-url" class="sr-only">Share link</label>
            <input
              id="record-share-url"
              :value="shareUrl"
              readonly
              class="w-full rounded-base border border-gray-300 px-3 py-2 text-caption text-gray-700"
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
        </div>

        <form v-else class="space-y-4" novalidate @submit.prevent="createLink">
          <div>
            <label for="record-share-expiry" class="mb-1 block text-body-sm font-medium text-gray-700">
              Link expires
            </label>
            <select
              id="record-share-expiry"
              v-model="expiresIn"
              class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
            >
              <option v-for="option in EXPIRY_OPTIONS" :key="option.value" :value="option.value">
                {{ option.label }}
              </option>
            </select>
          </div>

          <div>
            <label class="flex items-center gap-2 text-body-sm text-gray-700">
              <input v-model="usePassword" type="checkbox" class="rounded accent-primary-600" />
              Ask for a password
            </label>
            <input
              v-if="usePassword"
              v-model="password"
              type="text"
              placeholder="Something you can say over the phone"
              aria-label="Share password"
              class="mt-2 w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
            />
          </div>

          <button
            type="submit"
            :disabled="creating || (usePassword && !password.trim())"
            class="w-full rounded-base bg-primary-600 py-2.5 text-body-sm font-semibold text-white transition hover:bg-primary-700 disabled:opacity-60"
          >
            {{ creating ? "Creating…" : "Create link" }}
          </button>
        </form>

        <!-- What the person at the other end gets, said plainly. -->
        <div class="rounded-base bg-gray-50 p-4 text-caption text-gray-600">
          <p class="mb-1.5 font-medium text-gray-700">Anyone with the link can see</p>
          <ul class="space-y-1">
            <li>
              <i class="fas fa-check mr-1.5 text-success-600" aria-hidden="true"></i>
              This record's details, read-only
            </li>
            <li>
              <i class="fas fa-check mr-1.5 text-success-600" aria-hidden="true"></i>
              {{ documentCount }} attached
              {{ documentCount === 1 ? "document" : "documents" }}, to view and download
            </li>
            <li>
              <i class="fas fa-xmark mr-1.5 text-gray-400" aria-hidden="true"></i>
              Not your passwords — those stay encrypted and never travel down a link
            </li>
          </ul>
        </div>

        <!-- Links already out, and the way to pull them back. -->
        <div v-if="existing.length">
          <h3 class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500">
            Links you've shared
          </h3>
          <ul class="space-y-2">
            <li
              v-for="share in existing"
              :key="share.id"
              class="flex items-center justify-between gap-3 rounded-base border border-gray-200 px-3 py-2"
            >
              <div class="min-w-0">
                <p class="text-body-sm text-gray-800">{{ expiryLabel(share) }}</p>
                <p class="text-caption text-gray-500">
                  {{ share.download_count }} download{{ share.download_count === 1 ? "" : "s" }}
                </p>
              </div>
              <button
                type="button"
                class="shrink-0 text-body-sm font-medium text-error-600 hover:text-error-700"
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
