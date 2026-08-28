<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from "vue";
import api from "@/api/client";
import { useAuthStore } from "@/stores/auth";

/**
 * Sharing a whole album, two ways.
 *
 * With the family, which is a grant naming them on the album itself — the
 * permission check and the listing both already follow a folder's access down
 * to the photographs inside it, so one grant shares the lot and removing it
 * takes the lot back.
 *
 * Or with anybody, on a link that stops working on a date. Grandparents who
 * will never have an account get a page of the holiday and nothing else.
 */
const props = defineProps({
  album: { type: Object, required: true },
});
const emit = defineEmits(["close", "changed"]);

const auth = useAuthStore();

const EXPIRY_OPTIONS = [
  { value: "24h", label: "24 hours" },
  { value: "7d", label: "7 days" },
  { value: "30d", label: "30 days" },
  { value: "90d", label: "90 days" },
];

const grants = ref([]);
const links = ref([]);
const expiresIn = ref("30d");
const usePassword = ref(false);
const password = ref("");
const creating = ref(false);
const busy = ref(false);
const error = ref("");
const shareUrl = ref("");
const copied = ref(false);
const closeButton = ref(null);
let previouslyFocused = null;

const familyGrant = computed(() =>
  grants.value.find((g) => g.subject?.type === "Family" || g.subject_type === "Family"),
);

onMounted(async () => {
  previouslyFocused = document.activeElement;
  await nextTick();
  closeButton.value?.focus();
  document.addEventListener("keydown", onKeydown);
  load();
});

onBeforeUnmount(() => {
  document.removeEventListener("keydown", onKeydown);
  previouslyFocused?.focus?.();
});

function onKeydown(event) {
  if (event.key === "Escape") emit("close");
}

async function load() {
  try {
    const [grantsRes, linksRes] = await Promise.all([
      api.get(`/folders/${props.album.id}/grants`),
      api.get(`/folders/${props.album.id}/shares`),
    ]);
    grants.value = grantsRes.data.grants ?? [];
    links.value = linksRes.data.shares ?? [];
  } catch {
    // The dialog still works for making a link without the lists.
  }
}

async function setFamily(shared) {
  busy.value = true;
  error.value = "";

  try {
    if (shared) {
      await api.post(`/folders/${props.album.id}/grants`, {
        family_id: auth.family.id,
        role: "viewer",
      });
    } else if (familyGrant.value) {
      await api.delete(`/grants/${familyGrant.value.id}`);
    }
    await load();
    emit("changed");
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    busy.value = false;
  }
}

async function createLink() {
  creating.value = true;
  error.value = "";

  try {
    const { data } = await api.post(`/folders/${props.album.id}/shares`, {
      expires_in: expiresIn.value,
      password: usePassword.value ? password.value : undefined,
    });
    shareUrl.value = data.share.url;
    await load();
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
    error.value = "Couldn't copy — select the link and copy it manually.";
  }
}

async function revoke(link) {
  await api.delete(`/shares/${link.id}`);
  links.value = links.value.filter((l) => l.id !== link.id);
  if (!links.value.length) shareUrl.value = "";
}
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-gray-900/50 p-4"
    @click.self="emit('close')"
  >
    <div
      class="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-xl bg-white shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-labelledby="album-share-title"
    >
      <header class="flex items-start justify-between border-b border-gray-200 p-6">
        <div class="min-w-0">
          <h2 id="album-share-title" class="text-h3 font-semibold text-gray-800">Share this album</h2>
          <p class="mt-1 truncate text-body-sm text-gray-500">
            {{ album.name }} · {{ album.file_count }}
            {{ album.file_count === 1 ? "photo" : "photos" }}
          </p>
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

      <div class="space-y-6 p-6">
        <p v-if="error" role="alert" class="rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
          {{ error }}
        </p>

        <!-- Inside the house. -->
        <section v-if="auth.family">
          <label class="flex cursor-pointer items-start gap-3">
            <input
              type="checkbox"
              class="mt-1 rounded accent-primary-600"
              :checked="Boolean(familyGrant)"
              :disabled="busy"
              @change="setFamily($event.target.checked)"
            />
            <span class="min-w-0">
              <span class="block text-body-sm font-medium text-gray-800">
                Everyone in {{ auth.family.name }}
              </span>
              <span class="block text-caption text-gray-500">
                They see the whole album, and anything you add to it later. Turning this off takes
                it all back.
              </span>
            </span>
          </label>
        </section>

        <!-- And outside it. -->
        <section class="border-t border-gray-200 pt-6">
          <h3 class="text-body-sm font-medium text-gray-800">Anyone with a link</h3>
          <p class="mt-0.5 text-caption text-gray-500">
            No account needed. They can look and download, nothing else.
          </p>

          <div v-if="shareUrl" class="mt-3 rounded-base border border-success-100 bg-success-50 p-4">
            <p class="mb-2 text-body-sm font-medium text-success-700">
              <i class="fas fa-circle-check mr-1.5" aria-hidden="true"></i>
              Copy it now — it isn't shown again.
            </p>
            <div class="flex gap-2">
              <label for="album-share-url" class="sr-only">Share link</label>
              <input
                id="album-share-url"
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

          <form v-else class="mt-3 space-y-3" novalidate @submit.prevent="createLink">
            <div>
              <label for="album-expiry" class="mb-1 block text-body-sm font-medium text-gray-700">
                Stops working after
              </label>
              <select
                id="album-expiry"
                v-model="expiresIn"
                class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
              >
                <option v-for="option in EXPIRY_OPTIONS" :key="option.value" :value="option.value">
                  {{ option.label }}
                </option>
              </select>
            </div>

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
              class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
            />

            <button
              type="submit"
              :disabled="creating || (usePassword && !password.trim())"
              class="w-full rounded-base bg-primary-600 py-2.5 text-body-sm font-semibold text-white transition hover:bg-primary-700 disabled:opacity-60"
            >
              {{ creating ? "Creating…" : "Create a link" }}
            </button>
          </form>

          <ul v-if="links.length" class="mt-4 space-y-2">
            <li
              v-for="link in links"
              :key="link.id"
              class="flex items-center justify-between gap-3 rounded-base border border-gray-200 px-3 py-2"
            >
              <div class="min-w-0">
                <p class="text-body-sm text-gray-800">
                  {{
                    link.expires_at
                      ? `Expires ${new Date(link.expires_at).toLocaleDateString()}`
                      : "Never expires"
                  }}
                </p>
                <p class="text-caption text-gray-500">
                  {{ link.download_count }} download{{ link.download_count === 1 ? "" : "s" }}
                </p>
              </div>
              <button
                type="button"
                class="shrink-0 text-body-sm font-medium text-error-600 hover:underline"
                @click="revoke(link)"
              >
                Revoke
              </button>
            </li>
          </ul>
        </section>
      </div>
    </div>
  </div>
</template>
