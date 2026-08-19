<script setup>
import { onMounted, ref } from "vue";
import { useRoute } from "vue-router";
import api from "@/api/client";
import { formatFileSize, fileIcon } from "@/utils/formatting";

const route = useRoute();

const share = ref(null);
const loading = ref(true);
const downloading = ref(false);
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

async function download() {
  downloading.value = true;
  error.value = "";

  try {
    const { data } = await api.post(`/shares/${route.params.token}/download`, {
      password: password.value || undefined,
    });
    window.location.assign(data.url);
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    downloading.value = false;
  }
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-gray-50 p-4">
    <div class="w-full max-w-md">
      <div class="mb-6 flex items-center justify-center gap-2">
        <i class="fas fa-cloud text-2xl text-primary-600" aria-hidden="true"></i>
        <span class="text-h3 font-bold text-gray-800">CloudVault</span>
      </div>

      <div class="rounded-xl bg-white p-8 text-center shadow-lg">
        <div v-if="loading" class="py-8">
          <i class="fas fa-circle-notch fa-spin text-2xl text-gray-400" aria-hidden="true"></i>
          <p class="mt-3 text-body text-gray-500">Opening shared file…</p>
        </div>

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

          <form class="mt-6 space-y-4" novalidate @submit.prevent="download">
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
