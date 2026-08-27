<script setup>
import { computed, onMounted, ref } from "vue";
import { useRoute } from "vue-router";
import api from "@/api/client";
import FilePreview from "@/components/files/FilePreview.vue";
import RecordAttachmentPicker from "@/components/records/RecordAttachmentPicker.vue";
import RecordBreadcrumb from "@/components/records/RecordBreadcrumb.vue";
import RecordIcon from "@/components/records/RecordIcon.vue";
import RecordSecretDisplay from "@/components/records/RecordSecretDisplay.vue";
import RecordSecretInput from "@/components/records/RecordSecretInput.vue";
import { useVaultGate } from "@/composables/useVaultGate";
import { copyText } from "@/utils/clipboard";
import { fileIcon } from "@/utils/formatting";

const route = useRoute();
const vaultGate = useVaultGate();

const record = ref(null);
const loading = ref(true);
const error = ref("");
const editing = ref(false);
const saving = ref(false);
const copied = ref("");
const previewFile = ref(null);
const attachmentIds = ref([]);

const editForm = ref({ title: "", data: {} });
const secretDrafts = ref({});

/** Fields worth calling out at the top — references, expiries, emails, login details. */
const isLogin = computed(() => record.value?.record_type === "login");

const keyFields = computed(() => {
  const fields = record.value?.fields ?? [];
  if (isLogin.value) {
    return fields.filter((f) => f.value && (f.kind === "url" || f.key === "username"));
  }
  return fields.filter(
    (f) => f.value && [ "reference", "expiry", "email", "phone", "date", "money" ].includes(f.kind),
  );
});

const otherFields = computed(() => {
  const fields = record.value?.fields ?? [];
  if (isLogin.value) return [];
  return fields.filter(
    (f) => f.value && ![ "reference", "expiry", "email", "phone", "date", "money" ].includes(f.kind),
  );
});

const breadcrumbs = computed(() => [
  { label: "Register", to: { name: "household-register" } },
  { label: record.value?.title ?? "…" },
]);

const loginWebsite = computed(() => {
  if (!isLogin.value) return "";
  return record.value?.data?.website ?? record.value?.website ?? "";
});

onMounted(load);

async function load() {
  loading.value = true;
  error.value = "";
  try {
    const { data } = await api.get(`/records/${route.params.id}`);
    record.value = data.record;
    attachmentIds.value = (data.record.attachments ?? []).map((a) => a.file_id);
    editForm.value = {
      title: data.record.title,
      data: { ...data.record.data },
    };
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}

function startEdit() {
  attachmentIds.value = (record.value.attachments ?? []).map((a) => a.file_id);
  secretDrafts.value = {};
  editing.value = true;
}

function cancelEdit() {
  editing.value = false;
  attachmentIds.value = (record.value.attachments ?? []).map((a) => a.file_id);
  secretDrafts.value = {};
  editForm.value = {
    title: record.value.title,
    data: { ...record.value.data },
  };
}

function setSecretDraft(key, value) {
  secretDrafts.value = { ...secretDrafts.value, [key]: value };
}

async function save() {
  const touchedSecrets = Object.fromEntries(
    Object.entries(secretDrafts.value).filter(([, value]) => value !== undefined),
  );
  if (Object.keys(touchedSecrets).length && !(await vaultGate.ensureUnlocked())) return;

  saving.value = true;
  error.value = "";
  try {
    const payload = {
      record: {
        title: editForm.value.title.trim(),
        data: editForm.value.data,
      },
      attachment_ids: attachmentIds.value,
    };

    if (Object.keys(touchedSecrets).length) {
      payload.secrets = touchedSecrets;
    }

    const { data } = await api.patch(`/records/${record.value.id}`, payload);
    record.value = data.record;
    attachmentIds.value = (data.record.attachments ?? []).map((a) => a.file_id);
    secretDrafts.value = {};
    editing.value = false;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    saving.value = false;
  }
}

async function copy(value, token) {
  const ok = await copyText(value);
  copied.value = ok ? token : "";
  if (ok) setTimeout(() => (copied.value = ""), 2000);
}

function relationLabel(relation) {
  return relation.replace(/_/g, " ");
}

function siteHref(url) {
  const trimmed = url?.trim();
  if (!trimmed) return "";
  return /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
}

function openPreview(attachment) {
  previewFile.value = {
    id: attachment.file_id,
    name: attachment.name,
    mime_type: attachment.mime_type,
    size: attachment.size,
  };
}
</script>

<template>
  <section class="mx-auto max-w-xl">
    <RecordBreadcrumb :crumbs="breadcrumbs" />

    <div v-if="loading" class="space-y-3">
      <div class="h-8 w-2/3 animate-pulse rounded-base bg-gray-100"></div>
      <div class="h-32 animate-pulse rounded-base bg-gray-100"></div>
    </div>

    <p v-else-if="error && !record" role="alert" class="rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
      {{ error }}
    </p>

    <template v-else-if="record">
      <header class="mb-6 flex items-start justify-between gap-4">
        <div class="flex min-w-0 items-start gap-3">
          <RecordIcon
            v-if="isLogin && !editing"
            :title="record.title"
            :website="loginWebsite"
            size="lg"
            class="mt-1"
          />
          <div class="min-w-0">
            <p class="text-caption text-gray-500">{{ record.type_label }}</p>
            <h1 v-if="!editing" class="mt-0.5 text-h2 font-bold text-gray-800">{{ record.title }}</h1>
            <input
              v-else
              v-model="editForm.title"
              type="text"
              class="mt-1 w-full rounded-base border border-gray-300 px-3 py-2 text-h3 font-bold text-gray-800 outline-none focus:ring-2 focus:ring-primary-500"
            />
          </div>
        </div>

        <div v-if="record.permissions?.can_edit" class="flex shrink-0 gap-2">
          <template v-if="editing">
            <button
              type="button"
              class="text-body-sm font-medium text-gray-600 hover:text-gray-800"
              @click="cancelEdit"
            >
              Cancel
            </button>
            <button
              type="button"
              :disabled="saving"
              class="rounded-base bg-primary-600 px-3 py-1.5 text-body-sm font-medium text-white hover:bg-primary-700 disabled:opacity-60"
              @click="save"
            >
              {{ saving ? "Saving…" : "Save" }}
            </button>
          </template>
          <button
            v-else
            type="button"
            class="text-body-sm font-medium text-primary-600 hover:text-primary-700"
            @click="startEdit"
          >
            Edit
          </button>
        </div>
      </header>

      <p v-if="error" role="alert" class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
        {{ error }}
      </p>

      <div class="space-y-8">
        <!-- Key details / login -->
        <section v-if="(keyFields.length || (isLogin && record.secrets?.length)) && !editing">
          <h2 v-if="!isLogin" class="mb-3 text-body-sm font-medium text-gray-700">Key details</h2>
          <dl :class="isLogin ? 'space-y-4' : 'space-y-3'">
            <div v-for="field in keyFields" :key="field.key" class="flex items-start gap-2">
              <dt class="w-36 shrink-0 text-body-sm text-gray-500">{{ field.label }}</dt>
              <dd class="min-w-0 flex-1 break-words text-body-sm font-medium text-gray-800">
                <a
                  v-if="field.kind === 'url'"
                  :href="siteHref(field.value)"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-primary-600 hover:underline"
                >
                  {{ field.value }}
                </a>
                <template v-else>{{ field.value }}</template>
              </dd>
              <button
                v-if="field.kind !== 'url'"
                type="button"
                class="shrink-0 text-gray-400 hover:text-gray-700"
                :aria-label="`Copy ${field.label}`"
                @click="copy(field.value, field.key)"
              >
                <i
                  :class="['fas', copied === field.key ? 'fa-check text-success-600' : 'fa-copy']"
                  aria-hidden="true"
                ></i>
              </button>
              <a
                v-else
                :href="siteHref(field.value)"
                target="_blank"
                rel="noopener noreferrer"
                class="shrink-0 text-gray-400 hover:text-primary-600"
                aria-label="Open site"
              >
                <i class="fas fa-arrow-up-right-from-square" aria-hidden="true"></i>
              </a>
            </div>
            <RecordSecretDisplay
              v-for="secret in isLogin ? record.secrets : []"
              :key="secret.key"
              :record-id="record.id"
              :secret="secret"
            />
          </dl>
        </section>

        <!-- Edit fields -->
        <section v-if="editing" class="space-y-4">
          <div v-for="field in record.template?.fields?.filter((f) => f.kind !== 'secret')" :key="field.key">
            <label :for="`edit-${field.key}`" class="mb-1 block text-body-sm font-medium text-gray-700">
              {{ field.label }}
            </label>
            <textarea
              v-if="field.kind === 'multiline'"
              :id="`edit-${field.key}`"
              v-model="editForm.data[field.key]"
              rows="2"
              class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
            ></textarea>
            <input
              v-else
              :id="`edit-${field.key}`"
              v-model="editForm.data[field.key]"
              :type="field.kind === 'date' || field.kind === 'expiry' ? 'date' : field.kind === 'email' ? 'email' : 'text'"
              :inputmode="field.kind === 'url' ? 'url' : undefined"
              class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
            />
          </div>

          <template v-if="record.secrets?.length">
            <p class="text-body-sm font-medium text-gray-700">Passwords</p>
            <RecordSecretInput
              v-for="secret in record.secrets"
              :key="secret.key"
              :field="secret"
              :saved="secret.set"
              :model-value="secretDrafts[secret.key] ?? ''"
              @update:model-value="setSecretDraft(secret.key, $event)"
            />
          </template>
        </section>

        <!-- Secrets (non-login types) -->
        <section v-if="record.secrets?.length && !editing && !isLogin">
          <h2 class="mb-3 text-body-sm font-medium text-gray-700">Passwords</h2>
          <dl class="space-y-4">
            <RecordSecretDisplay
              v-for="secret in record.secrets"
              :key="secret.key"
              :record-id="record.id"
              :secret="secret"
            />
          </dl>
        </section>

        <!-- More details -->
        <section v-if="otherFields.length && !editing">
          <h2 class="mb-3 text-body-sm font-medium text-gray-700">More</h2>
          <dl class="space-y-3">
            <div v-for="field in otherFields" :key="field.key">
              <dt class="text-body-sm text-gray-500">{{ field.label }}</dt>
              <dd class="whitespace-pre-wrap text-body-sm text-gray-800">{{ field.value }}</dd>
            </div>
          </dl>
        </section>

        <!-- Documents -->
        <section v-if="!isLogin || editing || record.attachments?.length">
          <h2 class="mb-3 text-body-sm font-medium text-gray-700">Documents</h2>
          <RecordAttachmentPicker
            v-if="editing"
            v-model="attachmentIds"
            :visibility="record.visibility"
          />
          <ul v-else-if="record.attachments?.length" class="space-y-1">
            <li v-for="file in record.attachments" :key="file.id">
              <button
                type="button"
                class="flex w-full items-center gap-2 py-1 text-left text-body-sm text-gray-800 hover:text-primary-600"
                @click="openPreview(file)"
              >
                <i :class="['fas text-gray-400', fileIcon(file)]" aria-hidden="true"></i>
                <span class="truncate">{{ file.name }}</span>
              </button>
            </li>
          </ul>
          <p v-else-if="!editing" class="text-body-sm text-gray-500">
            None linked.
            <button
              v-if="record.permissions?.can_edit"
              type="button"
              class="font-medium text-primary-600 hover:text-primary-700"
              @click="startEdit"
            >
              Add
            </button>
          </p>
        </section>

        <!-- Links -->
        <section v-if="record.links?.length && !editing">
          <h2 class="mb-3 text-body-sm font-medium text-gray-700">Related</h2>
          <ul class="space-y-1">
            <li v-for="link in record.links" :key="link.id">
              <RouterLink
                :to="{ name: 'record', params: { id: link.record.id } }"
                class="text-body-sm text-gray-800 hover:text-primary-600"
              >
                <span class="text-gray-500">{{ relationLabel(link.relation) }}</span>
                {{ link.record.title }}
              </RouterLink>
            </li>
          </ul>
        </section>
      </div>

      <FilePreview v-if="previewFile" :file="previewFile" @close="previewFile = null" />
    </template>
  </section>
</template>
