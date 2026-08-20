<script setup>
import { computed, onMounted, ref } from "vue";
import api from "@/api/client";
import { useAuthStore } from "@/stores/auth";
import { useFilesStore } from "@/stores/files";
import { useDialog } from "@/composables/useDialog";
import { useToast } from "@/composables/useToast";
import FilePreview from "@/components/files/FilePreview.vue";
import { formatFileSize, formatRelativeDate, fileIcon } from "@/utils/formatting";

/**
 * Two different meanings of "shared", kept apart because they answer different
 * questions: what has my family put here that I did not, and what have I sent
 * out of the vault to people who have no account.
 */
const auth = useAuthStore();
const filesStore = useFilesStore();
const dialog = useDialog();
const toast = useToast();

const tab = ref("with-me");
const links = ref([]);
const loadingLinks = ref(true);
const error = ref("");
const previewFile = ref(null);
const refreshing = ref(false);

const liveLinks = computed(() => links.value.filter((l) => l.status === "active"));

onMounted(load);

async function load() {
  error.value = "";

  filesStore.fetchFiles({ filters: { shared_with_me: "true", sort: "newest" } });

  loadingLinks.value = true;
  try {
    const { data } = await api.get("/shares");
    links.value = data.shares;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loadingLinks.value = false;
  }
}

async function refresh() {
  refreshing.value = true;
  try {
    await load();
  } finally {
    refreshing.value = false;
  }
}

async function revoke(link) {
  const ok = await dialog.confirm({
    title: "Revoke this link?",
    message: `Anyone holding it loses access to "${link.file.name}" immediately.`,
    detail: link.download_count
      ? `It has been downloaded ${link.download_count} ${link.download_count === 1 ? "time" : "times"}.`
      : "It has not been downloaded yet.",
    confirmLabel: "Revoke link",
    danger: true,
  });
  if (!ok) return;

  try {
    await api.delete(`/shares/${link.id}`);
    links.value = links.value.filter((l) => l.id !== link.id);
    toast.show({ message: "Link revoked", detail: link.file.name });
  } catch (e) {
    error.value = e.userMessage;
  }
}

async function onDownload(file) {
  try {
    await filesStore.download(file);
  } catch (e) {
    filesStore.error = e.userMessage;
  }
}

function expiryLabel(link) {
  if (!link.expires_at) return "Never expires";

  const days = Math.ceil((new Date(link.expires_at) - Date.now()) / 86_400_000);
  if (days <= 0) return "Expired";
  return `Expires in ${days} ${days === 1 ? "day" : "days"}`;
}
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-center justify-between gap-4">
      <div>
        <h1 class="text-h2 font-bold text-gray-800">Shared</h1>
        <p class="mt-1 text-body-sm text-gray-500">
          What your family has shared with you, and what you have sent out
        </p>
      </div>

      <button
        type="button"
        :disabled="refreshing"
        class="rounded-base border border-gray-300 px-3 py-2 text-body font-medium text-gray-700 transition hover:bg-gray-50 disabled:opacity-60"
        aria-label="Refresh"
        @click="refresh"
      >
        <i :class="['fas fa-rotate-right', refreshing ? 'fa-spin' : '']" aria-hidden="true"></i>
      </button>
    </header>

    <div class="mb-6 flex gap-2 border-b border-gray-200">
      <button
        v-for="option in [
          { value: 'with-me', label: 'Shared with me', count: filesStore.totalCount },
          { value: 'links', label: 'My public links', count: liveLinks.length },
        ]"
        :key="option.value"
        type="button"
        :aria-pressed="tab === option.value"
        :class="[
          '-mb-px border-b-2 px-4 py-2 text-body font-medium transition',
          tab === option.value
            ? 'border-primary-600 text-primary-700'
            : 'border-transparent text-gray-500 hover:text-gray-700',
        ]"
        @click="tab = option.value"
      >
        {{ option.label }}
        <span class="ml-1 text-caption text-gray-400">{{ option.count }}</span>
      </button>
    </div>

    <p
      v-if="error"
      role="alert"
      class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
    >
      {{ error }}
    </p>

    <!-- Shared with me -->
    <template v-if="tab === 'with-me'">
      <div v-if="filesStore.loading" class="space-y-2">
        <div v-for="n in 4" :key="n" class="h-16 animate-pulse rounded-lg bg-gray-100"></div>
      </div>

      <div
        v-else-if="filesStore.isEmpty"
        class="rounded-lg border border-gray-200 bg-white p-12 text-center"
      >
        <i class="fas fa-users text-4xl text-gray-300" aria-hidden="true"></i>
        <h2 class="mt-4 text-h3 font-semibold text-gray-800">Nothing shared with you yet</h2>
        <p class="mt-2 text-body text-gray-500">
          <template v-if="auth.family">
            Files someone in {{ auth.family.name }} marks as family will appear here.
          </template>
          <template v-else>Join a family to see what they share.</template>
        </p>
      </div>

      <ul v-else class="space-y-2">
        <li
          v-for="file in filesStore.items"
          :key="file.id"
          class="flex items-center gap-4 rounded-lg border border-gray-200 bg-white p-4 transition hover:shadow-md"
        >
          <img
            v-if="file.image?.thumbnail_url"
            :src="file.image.thumbnail_url"
            :alt="file.name"
            class="h-10 w-10 shrink-0 rounded object-cover"
            loading="lazy"
          />
          <i
            v-else
            :class="['fas', fileIcon(file).icon, fileIcon(file).className, 'text-xl']"
            aria-hidden="true"
          ></i>

          <div class="min-w-0 flex-1">
            <button
              type="button"
              class="block w-full truncate text-left text-body font-medium text-gray-800 hover:text-primary-600"
              @click="previewFile = file"
            >
              {{ file.name }}
            </button>
            <p class="text-caption text-gray-500">
              {{ formatFileSize(file.size) }} · {{ formatRelativeDate(file.created_at) }} ·
              shared by {{ file.owner.name }}
              <span v-if="file.folder"> · {{ file.folder.name }}</span>
            </p>
          </div>

          <div class="flex items-center gap-1">
            <button
              type="button"
              class="rounded-md p-2 text-gray-500 transition hover:bg-gray-100 hover:text-gray-700"
              :aria-label="`Preview ${file.name}`"
              @click="previewFile = file"
            >
              <i class="fas fa-eye" aria-hidden="true"></i>
            </button>
            <button
              type="button"
              class="rounded-md p-2 text-gray-500 transition hover:bg-gray-100 hover:text-gray-700"
              :aria-label="`Download ${file.name}`"
              @click="onDownload(file)"
            >
              <i class="fas fa-download" aria-hidden="true"></i>
            </button>
          </div>
        </li>
      </ul>
    </template>

    <!-- My public links -->
    <template v-else>
      <div v-if="loadingLinks" class="space-y-2">
        <div v-for="n in 3" :key="n" class="h-16 animate-pulse rounded-lg bg-gray-100"></div>
      </div>

      <div v-else-if="!links.length" class="rounded-lg border border-gray-200 bg-white p-12 text-center">
        <i class="fas fa-link text-4xl text-gray-300" aria-hidden="true"></i>
        <h2 class="mt-4 text-h3 font-semibold text-gray-800">No public links</h2>
        <p class="mt-2 text-body text-gray-500">
          Links you create from a file's share dialog are listed here so you can revoke them.
        </p>
      </div>

      <ul v-else class="space-y-2">
        <li
          v-for="link in links"
          :key="link.id"
          class="flex items-center gap-4 rounded-lg border border-gray-200 bg-white p-4"
        >
          <i
            :class="['fas', fileIcon(link.file).icon, fileIcon(link.file).className, 'text-xl']"
            aria-hidden="true"
          ></i>

          <div class="min-w-0 flex-1">
            <p class="truncate text-body font-medium text-gray-800">{{ link.file.name }}</p>
            <p class="text-caption text-gray-500">
              {{ expiryLabel(link) }} ·
              {{ link.download_count }}
              {{ link.download_count === 1 ? "download" : "downloads" }}
              <span v-if="link.password_protected"> · password protected</span>
              <span v-if="link.last_accessed_at">
                · last opened {{ formatRelativeDate(link.last_accessed_at) }}
              </span>
            </p>
          </div>

          <!-- The URL itself is deliberately not shown: it is returned once, at
               creation, and never stored in a form we could display. -->
          <button
            type="button"
            class="shrink-0 rounded-base border border-error-500 px-3 py-2 text-body-sm font-semibold text-error-600 transition hover:bg-error-50"
            @click="revoke(link)"
          >
            Revoke
          </button>
        </li>
      </ul>
    </template>

    <FilePreview
      v-if="previewFile"
      :file="previewFile"
      :files="filesStore.items"
      @navigate="previewFile = $event"
      @close="previewFile = null"
    />
  </section>
</template>
