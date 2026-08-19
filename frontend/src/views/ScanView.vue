<script setup>
import { computed, onBeforeUnmount, ref } from "vue";
import { useRoute } from "vue-router";
import api from "@/api/client";
import { formatFileSize } from "@/utils/formatting";

const route = useRoute();

const session = ref(null);
const loading = ref(true);
const error = ref("");
const pages = ref([]);
const uploading = ref(false);
const progress = ref(0);
const done = ref(null);
const mode = ref("pdf");
const style = ref("document");
const name = ref("");

const cameraInput = ref(null);
const libraryInput = ref(null);

const token = computed(() => route.params.token);
const totalBytes = computed(() => pages.value.reduce((sum, p) => sum + p.file.size, 0));

async function load() {
  try {
    const { data } = await api.get(`/scans/${token.value}`);
    session.value = data;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}
load();

function addFiles(event) {
  for (const file of Array.from(event.target.files ?? [])) {
    pages.value.push({
      id: `${Date.now()}-${file.name}-${pages.value.length}`,
      file,
      // Object URLs are revoked on removal and unmount; leaving them alive
      // holds the full-resolution photo in memory on a phone.
      url: URL.createObjectURL(file),
    });
  }
  event.target.value = "";
}

function removePage(page) {
  URL.revokeObjectURL(page.url);
  pages.value = pages.value.filter((p) => p.id !== page.id);
}

function movePage(index, delta) {
  const target = index + delta;
  if (target < 0 || target >= pages.value.length) return;

  const copy = [...pages.value];
  [copy[index], copy[target]] = [copy[target], copy[index]];
  pages.value = copy;
}

async function upload() {
  if (!pages.value.length) return;

  uploading.value = true;
  error.value = "";
  progress.value = 0;

  const form = new FormData();
  pages.value.forEach((page) => form.append("pages[]", page.file));
  form.append("mode", mode.value);
  form.append("style", style.value);
  if (name.value.trim()) form.append("name", name.value.trim());

  try {
    const { data } = await api.post(`/scans/${token.value}`, form, {
      // Phone uploads over a slow connection need a longer leash than the
      // default 30s.
      timeout: 180_000,
      onUploadProgress: (event) => {
        if (event.total) progress.value = Math.round((event.loaded * 100) / event.total);
      },
    });

    done.value = data;
    pages.value.forEach((page) => URL.revokeObjectURL(page.url));
    pages.value = [];
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    uploading.value = false;
  }
}

function scanMore() {
  done.value = null;
  name.value = "";
}

onBeforeUnmount(() => pages.value.forEach((page) => URL.revokeObjectURL(page.url)));
</script>

<template>
  <div class="min-h-screen bg-gray-50 pb-32">
    <header class="gradient-main px-4 py-5 text-white">
      <div class="mx-auto flex max-w-lg items-center gap-3">
        <i class="fas fa-cloud text-xl" aria-hidden="true"></i>
        <div class="min-w-0">
          <h1 class="text-h4 font-bold">Scan to CloudVault</h1>
          <p v-if="session" class="truncate text-caption text-white/80">
            {{ session.account }} · {{ session.destination.folder }}
            <span v-if="session.destination.visibility === 'family'"> · shared with family</span>
          </p>
        </div>
      </div>
    </header>

    <main class="mx-auto max-w-lg px-4 py-6">
      <p v-if="loading" class="text-center text-body text-gray-500">
        <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Checking the link…
      </p>

      <!-- Expired or tampered link -->
      <div
        v-else-if="!session"
        class="rounded-xl bg-white p-8 text-center shadow-sm"
      >
        <i class="fas fa-link-slash text-4xl text-gray-300" aria-hidden="true"></i>
        <h2 class="mt-4 text-h3 font-semibold text-gray-800">This link has expired</h2>
        <p class="mt-2 text-body text-gray-500">
          {{ error || "Open CloudVault on your computer and create a new scanning link." }}
        </p>
      </div>

      <!-- Finished -->
      <div v-else-if="done" class="rounded-xl bg-white p-8 text-center shadow-sm">
        <i class="fas fa-circle-check text-4xl text-success-500" aria-hidden="true"></i>
        <h2 class="mt-4 text-h3 font-semibold text-gray-800">Saved to CloudVault</h2>
        <ul class="mt-3 space-y-1">
          <li v-for="file in done.files" :key="file.id" class="text-body text-gray-600">
            {{ file.name }} · {{ formatFileSize(file.size) }}
          </li>
        </ul>
        <p class="mt-2 text-caption text-gray-500">{{ done.page_count }} page(s)</p>

        <button
          type="button"
          class="mt-6 w-full rounded-base gradient-main py-3 font-semibold text-white"
          @click="scanMore"
        >
          Scan something else
        </button>
      </div>

      <template v-else>
        <p
          v-if="error"
          role="alert"
          class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
        >
          {{ error }}
        </p>

        <!-- Capture buttons. `capture` opens the camera straight away, which is
             what makes this work without an app. -->
        <div class="grid grid-cols-2 gap-3">
          <button
            type="button"
            class="flex flex-col items-center gap-2 rounded-xl bg-white p-6 shadow-sm transition active:scale-95"
            @click="cameraInput.click()"
          >
            <i class="fas fa-camera text-2xl text-primary-600" aria-hidden="true"></i>
            <span class="text-body font-semibold text-gray-800">Take photo</span>
          </button>

          <button
            type="button"
            class="flex flex-col items-center gap-2 rounded-xl bg-white p-6 shadow-sm transition active:scale-95"
            @click="libraryInput.click()"
          >
            <i class="fas fa-images text-2xl text-secondary-600" aria-hidden="true"></i>
            <span class="text-body font-semibold text-gray-800">From gallery</span>
          </button>
        </div>

        <input
          ref="cameraInput"
          type="file"
          accept="image/*"
          capture="environment"
          class="sr-only"
          aria-label="Take a photo of the document"
          @change="addFiles"
        />
        <input
          ref="libraryInput"
          type="file"
          accept="image/*,.heic,.heif"
          multiple
          class="sr-only"
          aria-label="Choose photos"
          @change="addFiles"
        />

        <!-- Captured pages -->
        <section v-if="pages.length" class="mt-6">
          <h2 class="mb-2 text-label font-medium uppercase tracking-wide text-gray-500">
            {{ pages.length }} page{{ pages.length === 1 ? "" : "s" }} · {{ formatFileSize(totalBytes) }}
          </h2>

          <ul class="space-y-2">
            <li
              v-for="(page, index) in pages"
              :key="page.id"
              class="flex items-center gap-3 rounded-lg bg-white p-2 shadow-sm"
            >
              <img :src="page.url" alt="" class="h-16 w-16 shrink-0 rounded object-cover" />
              <span class="flex-1 text-body-sm text-gray-700">Page {{ index + 1 }}</span>

              <button
                type="button"
                class="rounded-md p-2 text-gray-400 disabled:opacity-30"
                :disabled="index === 0"
                :aria-label="`Move page ${index + 1} up`"
                @click="movePage(index, -1)"
              >
                <i class="fas fa-arrow-up" aria-hidden="true"></i>
              </button>
              <button
                type="button"
                class="rounded-md p-2 text-gray-400 disabled:opacity-30"
                :disabled="index === pages.length - 1"
                :aria-label="`Move page ${index + 1} down`"
                @click="movePage(index, 1)"
              >
                <i class="fas fa-arrow-down" aria-hidden="true"></i>
              </button>
              <button
                type="button"
                class="rounded-md p-2 text-error-500"
                :aria-label="`Remove page ${index + 1}`"
                @click="removePage(page)"
              >
                <i class="fas fa-xmark" aria-hidden="true"></i>
              </button>
            </li>
          </ul>

          <!-- Options -->
          <div class="mt-4 space-y-3 rounded-lg bg-white p-4 shadow-sm">
            <div>
              <label for="scan-name" class="mb-1 block text-body-sm font-medium text-gray-700">
                Name
              </label>
              <input
                id="scan-name"
                v-model="name"
                type="text"
                placeholder="Passport, Driving licence…"
                class="w-full rounded-base border border-gray-300 px-3 py-2 outline-none focus:ring-2 focus:ring-primary-500"
              />
            </div>

            <div>
              <span class="mb-1 block text-body-sm font-medium text-gray-700">Save as</span>
              <div class="grid grid-cols-2 gap-2">
                <button
                  v-for="option in [
                    { value: 'pdf', label: 'One PDF', icon: 'fa-file-pdf' },
                    { value: 'images', label: 'Separate photos', icon: 'fa-images' },
                  ]"
                  :key="option.value"
                  type="button"
                  :aria-pressed="mode === option.value"
                  :class="[
                    'rounded-base border p-3 text-body-sm font-medium transition',
                    mode === option.value
                      ? 'border-primary-600 bg-primary-50 text-primary-700'
                      : 'border-gray-300 text-gray-600',
                  ]"
                  @click="mode = option.value"
                >
                  <i :class="['fas', option.icon, 'mr-2']" aria-hidden="true"></i>{{ option.label }}
                </button>
              </div>
            </div>

            <div>
              <span class="mb-1 block text-body-sm font-medium text-gray-700">Style</span>
              <div class="grid grid-cols-2 gap-2">
                <button
                  v-for="option in [
                    { value: 'document', label: 'Document' },
                    { value: 'colour', label: 'Keep colour' },
                  ]"
                  :key="option.value"
                  type="button"
                  :aria-pressed="style === option.value"
                  :class="[
                    'rounded-base border p-3 text-body-sm font-medium transition',
                    style === option.value
                      ? 'border-primary-600 bg-primary-50 text-primary-700'
                      : 'border-gray-300 text-gray-600',
                  ]"
                  @click="style = option.value"
                >
                  {{ option.label }}
                </button>
              </div>
            </div>
          </div>
        </section>

        <p v-else class="mt-8 text-center text-body text-gray-500">
          Photograph each page. You can reorder or remove them before saving.
        </p>
      </template>
    </main>

    <!-- Fixed save bar, so it stays reachable one-handed -->
    <div
      v-if="session && !done && pages.length"
      class="fixed inset-x-0 bottom-0 border-t border-gray-200 bg-white p-4"
    >
      <div class="mx-auto max-w-lg">
        <div v-if="uploading" class="mb-2 h-1 w-full overflow-hidden rounded-full bg-gray-200">
          <div class="h-full bg-primary-600 transition-all" :style="{ width: `${progress}%` }"></div>
        </div>

        <button
          type="button"
          :disabled="uploading"
          class="w-full rounded-base gradient-main py-3 text-body font-semibold text-white disabled:opacity-60"
          @click="upload"
        >
          <span v-if="uploading">Saving… {{ progress }}%</span>
          <span v-else>
            Save {{ pages.length }} page{{ pages.length === 1 ? "" : "s" }} to CloudVault
          </span>
        </button>
      </div>
    </div>
  </div>
</template>
