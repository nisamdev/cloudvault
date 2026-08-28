<script setup>
import { computed, onMounted, ref } from "vue";
import { useRoute } from "vue-router";
import api from "@/api/client";
import { formatFileSize, fileIcon } from "@/utils/formatting";

const route = useRoute();

const HEIC_TYPES = ["image/heic", "image/heif", "image/avif"];

const share = ref(null);
const loading = ref(true);
const downloading = ref(null);
const password = ref("");
const error = ref("");
const unavailable = ref(false);

onMounted(async () => {
  try {
    const { data } = await api.get(`/shares/${route.params.token}`);
    share.value = data.share;
  } catch (e) {
    // The API answers identically for unknown, expired and revoked links, so
    // there is nothing more specific to say here.
    unavailable.value = true;
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
});

/** A link to a record shows its details and every document on it. */
const isRecord = computed(() => share.value?.kind === "record");
/** A link to an album shows the photographs in it. */
const isAlbum = computed(() => share.value?.kind === "album");

// Photos going down a public link are cleaned of where they were taken, and a
// HEIC has to be re-encoded to lose it — so the file that arrives is a JPEG.
// Saying so beats a recipient wondering why the extension changed.
const privacyNote = computed(() => {
  if (share.value?.file?.file_type !== "image") return null;

  return HEIC_TYPES.includes(share.value.file.mime_type)
    ? "Location and camera details are removed from shared photos. This one downloads as a JPEG."
    : "Location and camera details are removed from shared photos.";
});

/**
 * @param file the document to fetch, when the link is to a record. A record
 *   share has several, and the link only ever opens its own.
 */
async function download(file = null) {
  downloading.value = file?.id ?? "only";
  error.value = "";

  try {
    const { data } = await api.post(`/shares/${route.params.token}/download`, {
      password: password.value || undefined,
      file_id: file?.id,
    });
    window.location.assign(data.url);
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    downloading.value = null;
  }
}

function formatValue(detail) {
  if (!["date", "expiry"].includes(detail.kind)) return detail.value;

  // A bare date is a calendar day, not an instant: parsing it as UTC shows the
  // day before to anybody west of Greenwich.
  const [year, month, day] = detail.value.split("-").map(Number);
  if (!year || !month || !day) return detail.value;

  return new Date(year, month - 1, day).toLocaleDateString(undefined, { dateStyle: "long" });
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-gray-50 p-4">
    <div :class="['w-full', isRecord || isAlbum ? 'max-w-3xl' : 'max-w-md']">
      <div class="mb-6 flex items-center justify-center gap-2">
        <i class="fas fa-cloud text-2xl text-primary-600" aria-hidden="true"></i>
        <span class="text-h3 font-bold text-gray-800">CloudVault</span>
      </div>

      <div class="rounded-xl bg-white p-8 text-center shadow-lg">
        <div v-if="loading" class="py-8">
          <i class="fas fa-circle-notch fa-spin text-2xl text-gray-400" aria-hidden="true"></i>
          <p class="mt-3 text-body text-gray-500">Opening what was shared with you…</p>
        </div>

        <!-- An album: the photographs in it, and a way to keep them. -->
        <template v-else-if="isAlbum">
          <p class="text-caption uppercase tracking-wider text-gray-500">Shared album</p>
          <h1 class="mt-1 break-words text-h2 font-bold text-gray-800">{{ share.album.name }}</h1>
          <p class="mt-1 text-body-sm text-gray-500">
            {{ share.album.count }} {{ share.album.count === 1 ? "photo" : "photos" }} ·
            shared by {{ share.album.shared_by }}
          </p>
          <p v-if="share.expires_at" class="mt-1 text-caption text-gray-400">
            This link stops working
            {{ new Date(share.expires_at).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" }) }}
          </p>

          <p
            v-if="error"
            role="alert"
            class="mt-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
          >
            {{ error }}
          </p>

          <div v-if="share.requires_password" class="mt-6 text-left">
            <label for="share-password" class="mb-2 block text-body-sm font-medium text-gray-700">
              This album is password protected
            </label>
            <input
              id="share-password"
              v-model="password"
              type="password"
              autocomplete="off"
              placeholder="Enter password"
              class="w-full rounded-base border border-gray-300 px-4 py-2 outline-none focus:border-transparent focus:ring-2 focus:ring-primary-500"
            />
          </div>

          <ul class="mt-6 grid gap-3 border-t border-gray-200 pt-6 sm:grid-cols-2 lg:grid-cols-3">
            <li
              v-for="photo in share.album.photos"
              :key="photo.id"
              class="flex flex-col gap-2 rounded-base border border-gray-200 p-3 text-left"
            >
              <div class="min-w-0">
                <p class="truncate text-body-sm font-medium text-gray-800">{{ photo.name }}</p>
                <p class="truncate text-caption text-gray-500">
                  <template v-if="photo.place_name">{{ photo.place_name }} · </template>
                  {{ formatFileSize(photo.size) }}
                </p>
              </div>
              <button
                type="button"
                :disabled="downloading === photo.id || (share.requires_password && !password)"
                class="rounded-base bg-primary-600 px-3 py-1.5 text-body-sm font-medium text-white transition hover:bg-primary-700 disabled:opacity-50"
                @click="download(photo)"
              >
                <i
                  :class="['fas mr-1.5', downloading === photo.id ? 'fa-circle-notch fa-spin' : 'fa-download']"
                  aria-hidden="true"
                ></i>
                {{ downloading === photo.id ? "Preparing…" : "Download" }}
              </button>
            </li>
          </ul>

          <p class="mt-6 text-caption text-gray-400">
            Read-only. The link can be withdrawn at any time.
          </p>
        </template>

        <!-- A record: its details, and every document attached to it. -->
        <template v-else-if="isRecord">
          <p class="text-caption uppercase tracking-wider text-gray-500">
            {{ share.record.type_label }}
          </p>
          <h1 class="mt-1 break-words text-h2 font-bold text-gray-800">{{ share.record.title }}</h1>
          <p class="mt-1 text-body-sm text-gray-500">
            Shared by {{ share.record.shared_by }}
          </p>
          <p v-if="share.expires_at" class="mt-1 text-caption text-gray-400">
            This link stops working
            {{ new Date(share.expires_at).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" }) }}
          </p>

          <p
            v-if="error"
            role="alert"
            class="mt-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
          >
            {{ error }}
          </p>

          <div v-if="share.requires_password" class="mt-6 text-left">
            <label for="share-password" class="mb-2 block text-body-sm font-medium text-gray-700">
              This link is password protected
            </label>
            <input
              id="share-password"
              v-model="password"
              type="password"
              autocomplete="off"
              placeholder="Enter password"
              class="w-full rounded-base border border-gray-300 px-4 py-2 outline-none focus:border-transparent focus:ring-2 focus:ring-primary-500"
            />
          </div>

          <dl
            v-if="share.record.details.length"
            class="mt-6 grid gap-x-8 gap-y-4 border-t border-gray-200 pt-6 text-left sm:grid-cols-2"
          >
            <div v-for="detail in share.record.details" :key="detail.label" class="min-w-0">
              <dt class="text-caption uppercase tracking-wider text-gray-500">{{ detail.label }}</dt>
              <dd
                :class="[
                  'mt-0.5 break-words text-body text-gray-800',
                  ['reference', 'number'].includes(detail.kind) ? 'font-mono' : '',
                ]"
              >
                {{ formatValue(detail) }}
              </dd>
            </div>
          </dl>

          <section v-if="share.record.documents.length" class="mt-6 border-t border-gray-200 pt-6 text-left">
            <h2 class="mb-3 text-caption uppercase tracking-wider text-gray-500">Documents</h2>
            <ul class="space-y-2">
              <li
                v-for="file in share.record.documents"
                :key="file.id"
                class="flex items-center gap-3 rounded-base border border-gray-200 px-3 py-2"
              >
                <i :class="['fas shrink-0', fileIcon(file).icon, fileIcon(file).className]" aria-hidden="true"></i>
                <span class="min-w-0 flex-1">
                  <span class="block truncate text-body-sm text-gray-800">{{ file.name }}</span>
                  <span class="block text-caption text-gray-500">{{ formatFileSize(file.size) }}</span>
                </span>
                <button
                  type="button"
                  :disabled="downloading === file.id || (share.requires_password && !password)"
                  class="shrink-0 rounded-base bg-primary-600 px-3 py-1.5 text-body-sm font-medium text-white transition hover:bg-primary-700 disabled:opacity-50"
                  @click="download(file)"
                >
                  <i
                    :class="['fas mr-1.5', downloading === file.id ? 'fa-circle-notch fa-spin' : 'fa-download']"
                    aria-hidden="true"
                  ></i>
                  {{ downloading === file.id ? "Preparing…" : "Download" }}
                </button>
              </li>
            </ul>
          </section>

          <p class="mt-6 text-caption text-gray-400">
            Read-only. Nothing here can be changed, and the link can be withdrawn at any time.
          </p>
        </template>

        <template v-else-if="share">
          <i
            :class="['fas', fileIcon(share.file).icon, fileIcon(share.file).className, 'text-5xl']"
            aria-hidden="true"
          ></i>

          <h1 class="mt-4 break-words text-h3 font-semibold text-gray-800">
            {{ share.file.name }}
          </h1>
          <p class="mt-1 text-body-sm text-gray-500">
            {{ formatFileSize(share.file.size) }} · shared by {{ share.file.shared_by }}
          </p>
          <p v-if="share.expires_at" class="mt-1 text-caption text-gray-400">
            Link expires {{ new Date(share.expires_at).toLocaleDateString() }}
          </p>

          <p
            v-if="error"
            role="alert"
            class="mt-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
          >
            {{ error }}
          </p>

          <form class="mt-6 space-y-4" novalidate @submit.prevent="download()">
            <div v-if="share.requires_password" class="text-left">
              <label for="share-password" class="mb-2 block text-body-sm font-medium text-gray-700">
                This file is password protected
              </label>
              <input
                id="share-password"
                v-model="password"
                type="password"
                required
                autocomplete="off"
                placeholder="Enter password"
                class="w-full rounded-base border border-gray-300 px-4 py-2 outline-none focus:border-transparent focus:ring-2 focus:ring-primary-500"
              />
            </div>

            <button
              type="submit"
              :disabled="downloading || (share.requires_password && !password)"
              class="w-full rounded-base gradient-main py-2 font-semibold text-white transition hover:opacity-95 disabled:cursor-not-allowed disabled:opacity-60"
            >
              <span v-if="downloading">
                <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Preparing…
              </span>
              <span v-else>
                <i class="fas fa-download mr-2" aria-hidden="true"></i>Download
              </span>
            </button>
          </form>

          <p v-if="privacyNote" class="mt-4 flex items-start gap-2 text-left text-caption text-gray-500">
            <i class="fas fa-location-crosshairs mt-0.5" aria-hidden="true"></i>
            <span>{{ privacyNote }}</span>
          </p>
        </template>

        <template v-else-if="unavailable">
          <i class="fas fa-link-slash text-4xl text-gray-300" aria-hidden="true"></i>
          <h1 class="mt-4 text-h3 font-semibold text-gray-800">This link is no longer available</h1>
          <p class="mt-2 text-body text-gray-500">
            It may have expired, been revoked, or reached its download limit.
          </p>
        </template>
      </div>

      <p class="mt-4 text-center text-caption text-gray-400">
        Shared securely with CloudVault
      </p>
    </div>
  </div>
</template>
