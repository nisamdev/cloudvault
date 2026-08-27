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
import RecordValidity from "@/components/records/RecordValidity.vue";
import RecordFieldValue from "@/components/records/RecordFieldValue.vue";
import RecordHolderPicker from "@/components/records/RecordHolderPicker.vue";
import RecordShareModal from "@/components/records/RecordShareModal.vue";
import { useFilesStore } from "@/stores/files";
import { useVaultGate } from "@/composables/useVaultGate";
import { copyText } from "@/utils/clipboard";
import { fileIcon } from "@/utils/formatting";
import { sectionCrumb } from "@/utils/recordSection";

const route = useRoute();
const vaultGate = useVaultGate();
const filesStore = useFilesStore();
const sharing = ref(false);

const record = ref(null);
const loading = ref(true);
const error = ref("");
const editing = ref(false);
const saving = ref(false);
const copied = ref("");
const previewFile = ref(null);
const attachmentIds = ref([]);
const heldById = ref(null);

const editForm = ref({ title: "", data: {}, visibility: "private" });
const secretDrafts = ref({});

/** Fields worth calling out at the top — references, expiries, emails, login details. */
const isLogin = computed(() => record.value?.record_type === "login");

const filled = computed(() => (record.value?.fields ?? []).filter((f) => f.value));

/**
 * The dates that decide whether you have to do something today. These lead the
 * page, because knowing when things run out is what a register is for.
 */
const expiries = computed(() => filled.value.filter((f) => f.kind === "expiry"));

/** When the record knows when the term began, the strip can show how far through it is. */
const startedOn = computed(() => {
  const data = record.value?.data ?? {};
  return data.issued_on || data.purchased_on || data.bought_on || null;
});

/**
 * The number you came to copy. One field gets promoted to the top of the page —
 * a passport number, a policy number, a registration — because that is what
 * somebody opening this record almost always wants.
 */
const primaryReference = computed(() => {
  if (isLogin.value) return null;
  return filled.value.find((f) => f.kind === "reference") ?? null;
});

/** Everything else, in template order, as a scannable grid. */
const detailFields = computed(() => {
  const skip = new Set([
    ...expiries.value.map((f) => f.key),
    primaryReference.value?.key,
  ]);
  const fields = filled.value.filter((f) => !skip.has(f.key));

  return isLogin.value ? fields.filter((f) => f.key !== "name") : fields;
});

/** Long prose sits on its own row; short facts pair up. */
function isWide(field) {
  return field.kind === "multiline" || String(field.value ?? "").length > 60;
}

const editableFields = computed(
  () => record.value?.template?.fields?.filter((f) => f.kind !== "secret") ?? [],
);

const breadcrumbs = computed(() => [
  sectionCrumb(record.value?.template?.group),
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
  heldById.value = data.record.held_by?.id ?? null;
    editForm.value = {
      title: data.record.title,
      data: { ...data.record.data },
      visibility: data.record.visibility,
    };
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}

function startEdit() {
  attachmentIds.value = (record.value.attachments ?? []).map((a) => a.file_id);
  heldById.value = record.value.held_by?.id ?? null;
  secretDrafts.value = {};
  editing.value = true;
}

function cancelEdit() {
  editing.value = false;
  attachmentIds.value = (record.value.attachments ?? []).map((a) => a.file_id);
  heldById.value = record.value.held_by?.id ?? null;
  secretDrafts.value = {};
  editForm.value = {
    title: record.value.title,
    data: { ...record.value.data },
    visibility: record.value.visibility,
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
        visibility: editForm.value.visibility,
      },
      attachment_ids: attachmentIds.value,
      held_by_id: heldById.value,
    };

    if (Object.keys(touchedSecrets).length) {
      payload.secrets = touchedSecrets;
    }

    const { data } = await api.patch(`/records/${record.value.id}`, payload);
    record.value = data.record;
    attachmentIds.value = (data.record.attachments ?? []).map((a) => a.file_id);
  heldById.value = data.record.held_by?.id ?? null;
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

/** The attached document itself, straight to disk. */
async function downloadAttachment(attachment) {
  try {
    await filesStore.download({ id: attachment.file_id, name: attachment.name });
  } catch (e) {
    error.value = e.userMessage;
  }
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
  <section class="mx-auto max-w-5xl">
    <RecordBreadcrumb :crumbs="breadcrumbs" />

    <div v-if="loading" class="space-y-4">
      <div class="h-10 w-2/3 animate-pulse rounded-base bg-gray-100"></div>
      <div class="h-40 animate-pulse rounded-base bg-gray-100"></div>
    </div>

    <p v-else-if="error && !record" role="alert" class="rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
      {{ error }}
    </p>

    <template v-else-if="record">
      <!-- Identity. The record says what it is before it says anything else. -->
      <header class="flex flex-wrap items-start justify-between gap-4 border-b border-gray-200 pb-5">
        <div class="flex min-w-0 items-start gap-4">
          <RecordIcon
            :title="record.title"
            :website="loginWebsite"
            :type-icon="record.template?.icon"
            size="lg"
            class="mt-1"
          />
          <div class="min-w-0">
            <p class="text-caption uppercase tracking-wider text-gray-500">{{ record.type_label }}</p>
            <h1 v-if="!editing" class="mt-1 text-h2 font-bold text-gray-800">{{ record.title }}</h1>
            <input
              v-else
              v-model="editForm.title"
              type="text"
              aria-label="Title"
              class="mt-1 w-full border-b-2 border-primary-400 bg-transparent pb-1 text-h2 font-bold text-gray-800 outline-none"
            />
          </div>
        </div>

        <div v-if="record.permissions?.can_edit" class="flex shrink-0 items-center gap-3">
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
              class="rounded-base bg-primary-600 px-4 py-2 text-body-sm font-medium text-white hover:bg-primary-700 disabled:opacity-60"
              @click="save"
            >
              {{ saving ? "Saving…" : "Save changes" }}
            </button>
          </template>
          <template v-else>
            <button
              v-if="record.permissions?.can_edit"
              type="button"
              class="rounded-base border border-gray-300 px-4 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
              @click="sharing = true"
            >
              <i class="fas fa-share-nodes mr-2 text-gray-400" aria-hidden="true"></i>Share
            </button>
            <button
              type="button"
              class="rounded-base border border-gray-300 px-4 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
              @click="startEdit"
            >
              <i class="fas fa-pen mr-2 text-gray-400" aria-hidden="true"></i>Edit
            </button>
          </template>
        </div>
      </header>

      <p v-if="error" role="alert" class="mt-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
        {{ error }}
      </p>

      <!-- Substance on the left, what it is attached to on the right. -->
      <div class="mt-6 grid gap-x-10 gap-y-8 lg:grid-cols-[minmax(0,1fr)_18rem]">
        <div class="min-w-0 space-y-8">
          <!-- Reading -->
          <template v-if="!editing">
            <div v-if="expiries.length" class="space-y-4">
              <RecordValidity
                v-for="field in expiries"
                :key="field.key"
                :field="field"
                :value="field.value"
                :from="startedOn"
              />
            </div>

            <!-- The number you came to copy. -->
            <div v-if="primaryReference">
              <p class="text-caption uppercase tracking-wider text-gray-500">
                {{ primaryReference.label }}
              </p>
              <div class="mt-1 flex items-center gap-3">
                <p class="break-all font-mono text-h3 text-gray-800">{{ primaryReference.value }}</p>
                <button
                  type="button"
                  class="shrink-0 rounded-md p-1.5 text-gray-400 transition hover:bg-gray-100 hover:text-gray-700"
                  :aria-label="`Copy ${primaryReference.label}`"
                  @click="copy(primaryReference.value, primaryReference.key)"
                >
                  <i
                    :class="['fas', copied === primaryReference.key ? 'fa-check text-success-600' : 'fa-copy']"
                    aria-hidden="true"
                  ></i>
                </button>
              </div>
            </div>

            <section v-if="record.secrets?.length">
              <h2 class="mb-3 text-caption uppercase tracking-wider text-gray-500">
                {{ isLogin ? "Sign in" : "Passwords" }}
              </h2>
              <dl class="space-y-4">
                <RecordSecretDisplay
                  v-for="secret in record.secrets"
                  :key="secret.key"
                  :record-id="record.id"
                  :secret="secret"
                />
              </dl>
            </section>

            <section v-if="detailFields.length">
              <h2 class="mb-3 text-caption uppercase tracking-wider text-gray-500">Details</h2>
              <dl class="grid gap-x-8 gap-y-4 sm:grid-cols-2">
                <div
                  v-for="field in detailFields"
                  :key="field.key"
                  :class="['group min-w-0', isWide(field) ? 'sm:col-span-2' : '']"
                >
                  <dt class="text-caption uppercase tracking-wider text-gray-500">{{ field.label }}</dt>
                  <dd class="mt-0.5 flex items-start gap-2">
                    <RecordFieldValue class="min-w-0 flex-1" :field="field" :value="field.value" />
                    <button
                      v-if="field.kind !== 'url'"
                      type="button"
                      class="mt-0.5 shrink-0 text-gray-300 opacity-0 transition group-hover:opacity-100 focus:opacity-100 hover:text-gray-700"
                      :aria-label="`Copy ${field.label}`"
                      @click="copy(field.value, field.key)"
                    >
                      <i
                        :class="['fas text-caption', copied === field.key ? 'fa-check text-success-600' : 'fa-copy']"
                        aria-hidden="true"
                      ></i>
                    </button>
                  </dd>
                </div>
              </dl>
            </section>

            <p v-if="!expiries.length && !primaryReference && !detailFields.length && !record.secrets?.length"
               class="rounded-base border border-dashed border-gray-300 px-4 py-8 text-center text-body-sm text-gray-500">
              Nothing filled in yet.
              <button
                v-if="record.permissions?.can_edit"
                type="button"
                class="font-medium text-primary-600 hover:text-primary-700"
                @click="startEdit"
              >
                Add the details
              </button>
            </p>
          </template>

          <!-- Editing. Short facts pair up; prose gets a row to itself. -->
          <template v-else>
            <div class="grid gap-x-6 gap-y-4 sm:grid-cols-2">
              <div
                v-for="field in editableFields"
                :key="field.key"
                :class="field.kind === 'multiline' ? 'sm:col-span-2' : ''"
              >
                <label :for="`edit-${field.key}`" class="mb-1 block text-body-sm font-medium text-gray-700">
                  {{ field.label }}
                </label>
                <textarea
                  v-if="field.kind === 'multiline'"
                  :id="`edit-${field.key}`"
                  v-model="editForm.data[field.key]"
                  rows="3"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
                ></textarea>
                <input
                  v-else
                  :id="`edit-${field.key}`"
                  v-model="editForm.data[field.key]"
                  :type="field.kind === 'date' || field.kind === 'expiry' ? 'date' : field.kind === 'email' ? 'email' : 'text'"
                  :inputmode="field.kind === 'url' ? 'url' : undefined"
                  :class="[
                    'w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500',
                    ['reference', 'number'].includes(field.kind) ? 'font-mono' : '',
                  ]"
                />
                <p v-if="field.hint" class="mt-1 text-caption text-gray-500">{{ field.hint }}</p>
              </div>
            </div>

            <fieldset v-if="record.secrets?.length" class="rounded-base border border-gray-200 bg-gray-50 p-4">
              <legend class="px-1 text-body-sm font-medium text-gray-700">
                <i class="fas fa-lock mr-1.5 text-gray-400" aria-hidden="true"></i>Passwords
              </legend>
              <p class="mb-3 text-caption text-gray-500">
                Encrypted with your private section passphrase. Leave blank to keep what is saved.
              </p>
              <div class="space-y-4">
                <RecordSecretInput
                  v-for="secret in record.secrets"
                  :key="secret.key"
                  :field="secret"
                  :saved="secret.set"
                  :model-value="secretDrafts[secret.key] ?? ''"
                  @update:model-value="setSecretDraft(secret.key, $event)"
                />
              </div>
            </fieldset>
          </template>
        </div>

        <!-- What it is attached to -->
        <aside class="space-y-8 lg:border-l lg:border-gray-200 lg:pl-8">
          <!-- Whose it is. A person is not held by anybody, so the field is
               offered on everything else. -->
          <section v-if="record.record_type !== 'person'">
            <RecordHolderPicker
              v-if="editing"
              v-model="heldById"
              :exclude-id="record.id"
            />
            <template v-else-if="record.held_by">
              <h2 class="mb-2 text-caption uppercase tracking-wider text-gray-500">Whose is it</h2>
              <RouterLink
                :to="{ name: 'record', params: { id: record.held_by.id } }"
                class="flex items-center gap-2 text-body-sm font-medium text-gray-800 transition hover:text-primary-600"
              >
                <i class="fas fa-user text-gray-400" aria-hidden="true"></i>
                {{ record.held_by.name }}
              </RouterLink>
            </template>
          </section>

          <section>
            <h2 class="mb-3 text-caption uppercase tracking-wider text-gray-500">Documents</h2>
            <RecordAttachmentPicker
              v-if="editing"
              v-model="attachmentIds"
              :visibility="record.visibility"
            />
            <ul v-else-if="record.attachments?.length" class="space-y-1">
              <li
                v-for="file in record.attachments"
                :key="file.id"
                class="group flex items-center gap-1 rounded-base transition hover:bg-gray-50"
              >
                <button
                  type="button"
                  class="flex min-w-0 flex-1 items-center gap-2 px-2 py-1.5 text-left text-body-sm text-gray-800 transition hover:text-primary-600"
                  @click="openPreview(file)"
                >
                  <i :class="['fas shrink-0', fileIcon(file).icon, fileIcon(file).className]" aria-hidden="true"></i>
                  <span class="truncate">{{ file.name }}</span>
                </button>
                <!-- The scan is the thing you came for as often as the record
                     is: keeping it one click away saves opening a preview to
                     find the button. Always visible, never hover-only — half
                     the family reads this on a phone, where there is no hover.
                     -->
                <button
                  type="button"
                  class="shrink-0 rounded-md p-1.5 text-gray-400 transition hover:bg-gray-200 hover:text-gray-700"
                  :aria-label="`Download ${file.name}`"
                  :title="`Download ${file.name}`"
                  @click="downloadAttachment(file)"
                >
                  <i class="fas fa-arrow-down-to-line" aria-hidden="true"></i>
                </button>
              </li>
            </ul>
            <p v-else class="text-body-sm text-gray-500">
              None yet.
              <button
                v-if="record.permissions?.can_edit"
                type="button"
                class="font-medium text-primary-600 hover:text-primary-700"
                @click="startEdit"
              >
                Add one
              </button>
            </p>
          </section>

          <section v-if="record.links?.length">
            <h2 class="mb-3 text-caption uppercase tracking-wider text-gray-500">Related</h2>
            <ul class="space-y-2">
              <li v-for="link in record.links" :key="link.id">
                <RouterLink
                  :to="{ name: 'record', params: { id: link.record.id } }"
                  class="block rounded-base px-2 py-1 transition hover:bg-gray-50"
                >
                  <span class="block text-caption uppercase tracking-wider text-gray-400">
                    {{ relationLabel(link.relation) }}
                  </span>
                  <span class="text-body-sm text-gray-800">{{ link.record.title }}</span>
                </RouterLink>
              </li>
            </ul>
          </section>

          <section>
            <label
              for="record-visibility"
              class="mb-2 block text-caption uppercase tracking-wider text-gray-500"
            >
              Who can see it
            </label>
            <select
              v-if="editing"
              id="record-visibility"
              v-model="editForm.visibility"
              class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
            >
              <option value="private">Just me</option>
              <option value="family">My family</option>
            </select>
            <template v-else>
              <p class="text-body-sm text-gray-700">
                <i
                  :class="['fas mr-1.5 text-gray-400', record.visibility === 'family' ? 'fa-users' : 'fa-user']"
                  aria-hidden="true"
                ></i>
                {{ record.visibility === "family" ? "My family" : "Just me" }}
              </p>
              <button
                v-if="record.permissions?.can_edit && record.visibility !== 'family'"
                type="button"
                class="mt-1 text-body-sm font-medium text-primary-600 hover:text-primary-700"
                @click="startEdit"
              >
                Share with my family
              </button>
            </template>
          </section>
        </aside>
      </div>

      <FilePreview v-if="previewFile" :file="previewFile" @close="previewFile = null" />
      <RecordShareModal v-if="sharing" :record="record" @close="sharing = false" />
    </template>
  </section>
</template>
