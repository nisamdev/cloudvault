<script setup>
import { ref } from "vue";
import api from "@/api/client";
import { useVaultGate } from "@/composables/useVaultGate";
import { copyText } from "@/utils/clipboard";

const props = defineProps({
  recordId: { type: [Number, String], required: true },
  secret: { type: Object, required: true },
});

const vaultGate = useVaultGate();

const revealed = ref("");
const visible = ref(false);
const loading = ref(false);
const error = ref("");
const copied = ref(false);
const historyOpen = ref(false);
const history = ref([]);
const historyLoading = ref(false);

async function ensureOpen() {
  if (!(await vaultGate.ensureUnlocked())) {
    error.value = "Unlock the private section to read passwords.";
    return false;
  }
  return true;
}

async function fetchValue() {
  if (revealed.value) return revealed.value;

  const { data } = await api.get(`/records/${props.recordId}/secrets/${props.secret.key}/reveal`);
  revealed.value = data.value;
  return revealed.value;
}

async function toggleShow() {
  if (visible.value) {
    visible.value = false;
    return;
  }

  loading.value = true;
  error.value = "";
  try {
    if (!(await ensureOpen())) return;
    await fetchValue();
    visible.value = true;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}

async function copy() {
  loading.value = true;
  error.value = "";
  try {
    if (!(await ensureOpen())) return;
    await fetchValue();

    const ok = await copyText(revealed.value);
    copied.value = ok;
    if (ok) setTimeout(() => (copied.value = false), 2000);
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}

async function toggleHistory() {
  historyOpen.value = !historyOpen.value;
  if (!historyOpen.value || history.value.length) return;

  historyLoading.value = true;
  error.value = "";
  try {
    if (!(await ensureOpen())) {
      historyOpen.value = false;
      return;
    }

    const { data } = await api.get(`/records/${props.recordId}/secrets/${props.secret.key}/history`);
    history.value = data.versions ?? [];
  } catch (e) {
    error.value = e.userMessage;
    historyOpen.value = false;
  } finally {
    historyLoading.value = false;
  }
}

async function revealVersion(version) {
  loading.value = true;
  error.value = "";
  try {
    if (!(await ensureOpen())) return;

    const { data } = await api.get(
      `/records/${props.recordId}/secrets/${props.secret.key}/history/${version.id}/reveal`,
    );
    revealed.value = data.value;
    visible.value = true;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <div class="flex items-start gap-2">
    <dt class="w-36 shrink-0 text-body-sm text-gray-500">{{ secret.label }}</dt>
    <dd class="min-w-0 flex-1">
      <p v-if="!secret.set" class="text-body-sm text-gray-400">Not set</p>

      <template v-else>
        <p class="break-all font-mono text-body-sm font-medium text-gray-800">
          {{ visible && revealed ? revealed : "••••••••" }}
        </p>

        <button
          v-if="secret.history_count"
          type="button"
          class="mt-1 text-body-sm text-gray-500 hover:text-gray-700"
          @click="toggleHistory"
        >
          {{ historyOpen ? "Hide history" : `${secret.history_count} previous` }}
        </button>

        <ul v-if="historyOpen" class="mt-2 space-y-1 border-l border-gray-200 pl-3">
          <li v-if="historyLoading" class="text-caption text-gray-400">Loading…</li>
          <li v-for="version in history" :key="version.id">
            <button
              type="button"
              class="text-body-sm text-gray-600 hover:text-primary-600"
              @click="revealVersion(version)"
            >
              {{ new Date(version.replaced_at).toLocaleDateString() }}
            </button>
          </li>
        </ul>
      </template>

      <p v-if="error" role="alert" class="mt-1 text-caption text-error-600">{{ error }}</p>
    </dd>

    <div v-if="secret.set" class="flex shrink-0 gap-1">
      <button
        type="button"
        class="rounded p-1 text-gray-400 hover:text-gray-700 disabled:opacity-60"
        :disabled="loading"
        :aria-label="visible ? 'Hide password' : 'Show password'"
        :aria-pressed="visible"
        @click="toggleShow"
      >
        <i :class="['fas', visible ? 'fa-eye-slash' : 'fa-eye']" aria-hidden="true"></i>
      </button>
      <button
        type="button"
        class="rounded p-1 text-gray-400 hover:text-gray-700 disabled:opacity-60"
        :disabled="loading"
        aria-label="Copy password"
        @click="copy"
      >
        <i
          :class="['fas', copied ? 'fa-check text-success-600' : 'fa-copy']"
          aria-hidden="true"
        ></i>
      </button>
    </div>
  </div>
</template>
