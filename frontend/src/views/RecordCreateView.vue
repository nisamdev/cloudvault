<script setup>
import { computed, onMounted, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import api from "@/api/client";
import RecordAttachmentPicker from "@/components/records/RecordAttachmentPicker.vue";
import RecordBreadcrumb from "@/components/records/RecordBreadcrumb.vue";
import RecordIcon from "@/components/records/RecordIcon.vue";
import RecordSecretInput from "@/components/records/RecordSecretInput.vue";
import { useVaultGate } from "@/composables/useVaultGate";

const route = useRoute();
const router = useRouter();
const vaultGate = useVaultGate();

const template = ref(null);
const loading = ref(true);
const saving = ref(false);
const error = ref("");
const attachmentIds = ref([]);

const form = ref({
  title: "",
  visibility: "private",
  data: {},
  secrets: {},
});

const secretFields = computed(() =>
  (template.value?.fields ?? []).filter((f) => f.kind === "secret"),
);

const editableFields = computed(() =>
  (template.value?.fields ?? []).filter((f) => f.kind !== "secret"),
);

/** Some types name themselves from a field instead of a separate title. */
const TITLE_SOURCE_KEYS = ["full_name", "name"];

const titleFieldKey = computed(() =>
  TITLE_SOURCE_KEYS.find((key) => editableFields.value.some((f) => f.key === key)),
);

const showTitleField = computed(() => !titleFieldKey.value);

/** Login and similar — one tight block, no documents section. */
const isCompactForm = computed(() => template.value?.type === "login");

/** The field that names the record, kept out of the grid so it can lead. */
const identityField = computed(() =>
  titleFieldKey.value ? editableFields.value.find((f) => f.key === titleFieldKey.value) : null,
);

/** Everything else, which pairs up two to a row. */
const gridFields = computed(() =>
  editableFields.value.filter((f) => f.key !== titleFieldKey.value),
);

/** What the header shows while you are still typing the name. */
const workingTitle = computed(
  () => (titleFieldKey.value ? form.value.data[titleFieldKey.value] : form.value.title) || "",
);

const compactSecrets = computed(() => isCompactForm.value || secretFields.value.length === 1);

const breadcrumbs = computed(() => [
  { label: "Register", to: { name: "household-register" } },
  { label: "Add", to: { name: "record-new" } },
  { label: template.value?.label ?? "…" },
]);

onMounted(async () => {
  try {
    const { data } = await api.get("/record_templates");
    const match = data.templates.find((t) => t.type === route.params.type);
    if (!match) {
      router.replace({ name: "record-new" });
      return;
    }
    template.value = match;
    form.value.data = Object.fromEntries(
      match.fields.filter((f) => f.kind !== "secret").map((f) => [f.key, ""]),
    );
    form.value.secrets = Object.fromEntries(
      match.fields.filter((f) => f.kind === "secret").map((f) => [f.key, ""]),
    );
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
});

function inputType(field) {
  // type="url" rejects bare domains like "netflix.com" and blocks form submit silently.
  if (field.kind === "url") return "text";
  if (field.kind === "date" || field.kind === "expiry") return "date";
  if (field.kind === "email") return "email";
  return "text";
}

function normalizeData() {
  const data = { ...form.value.data };
  for (const field of editableFields.value) {
    if (field.kind !== "url") continue;
    const raw = data[field.key]?.trim();
    if (raw && !/^https?:\/\//i.test(raw)) {
      data[field.key] = `https://${raw}`;
    }
  }
  return data;
}

function resolvedTitle() {
  const manual = form.value.title.trim();
  if (manual) return manual;
  const key = titleFieldKey.value;
  if (key) {
    const fromField = form.value.data[key]?.trim();
    if (fromField) return fromField;
  }
  return template.value?.title_hint ?? template.value?.label ?? "Untitled";
}

function canSave() {
  if (showTitleField.value && !form.value.title.trim()) return false;
  if (titleFieldKey.value && !form.value.data[titleFieldKey.value]?.trim()) return false;
  return true;
}

async function save() {
  if (!template.value || !canSave()) return;

  const hasSecrets = secretFields.value.some((f) => form.value.secrets[f.key]?.trim());
  if (hasSecrets && !(await vaultGate.ensureUnlocked())) {
    error.value = "Set up or unlock your private section to save the password.";
    return;
  }

  saving.value = true;
  error.value = "";
  try {
    const payload = {
      record: {
        record_type: template.value.type,
        title: resolvedTitle(),
        visibility: form.value.visibility,
        data: normalizeData(),
      },
      attachment_ids: attachmentIds.value,
    };

    if (hasSecrets) {
      payload.secrets = Object.fromEntries(
        secretFields.value
          .filter((f) => form.value.secrets[f.key]?.trim())
          .map((f) => [f.key, form.value.secrets[f.key].trim()]),
      );
    }

    const { data } = await api.post("/records", payload);
    router.push({ name: "record", params: { id: data.record.id } });
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <section class="mx-auto max-w-5xl">
    <RecordBreadcrumb :crumbs="breadcrumbs" />

    <div v-if="loading" class="space-y-4">
      <div class="h-10 w-40 animate-pulse rounded-base bg-gray-100"></div>
      <div class="h-48 animate-pulse rounded-base bg-gray-100"></div>
    </div>

    <template v-else-if="template">
      <form @submit.prevent="save">
        <!-- The same header the record will have once it exists, filled in as
             you type. You are naming a thing, not completing a field. -->
        <header class="flex flex-wrap items-start justify-between gap-4 border-b border-gray-200 pb-5">
          <div class="flex min-w-0 flex-1 items-start gap-4">
            <RecordIcon
              :title="workingTitle"
              :website="form.data.website ?? ''"
              :type-icon="template.icon"
              size="lg"
              class="mt-1"
            />
            <div class="min-w-0 flex-1">
              <p class="text-caption uppercase tracking-wider text-gray-500">{{ template.label }}</p>
              <label :for="identityField ? `field-${identityField.key}` : 'record-title'" class="sr-only">
                {{ identityField ? identityField.label : "Title" }}
              </label>
              <input
                v-if="identityField"
                :id="`field-${identityField.key}`"
                v-model="form.data[identityField.key]"
                type="text"
                required
                autofocus
                :placeholder="template.title_hint"
                class="mt-1 w-full border-b-2 border-gray-200 bg-transparent pb-1 text-h2 font-bold text-gray-800 outline-none transition placeholder:font-normal placeholder:text-gray-300 focus:border-primary-400"
              />
              <input
                v-else
                id="record-title"
                v-model="form.title"
                type="text"
                required
                autofocus
                :placeholder="template.title_hint"
                class="mt-1 w-full border-b-2 border-gray-200 bg-transparent pb-1 text-h2 font-bold text-gray-800 outline-none transition placeholder:font-normal placeholder:text-gray-300 focus:border-primary-400"
              />
              <p v-if="identityField?.hint" class="mt-1 text-caption text-gray-500">
                {{ identityField.hint }}
              </p>
            </div>
          </div>

          <div class="flex shrink-0 items-center gap-3">
            <RouterLink
              :to="{ name: 'household-register' }"
              class="text-body-sm font-medium text-gray-600 hover:text-gray-800"
            >
              Cancel
            </RouterLink>
            <button
              type="submit"
              :disabled="saving || !canSave()"
              class="rounded-base bg-primary-600 px-4 py-2 text-body-sm font-medium text-white transition hover:bg-primary-700 disabled:opacity-50"
            >
              {{ saving ? "Saving…" : "Save" }}
            </button>
          </div>
        </header>

        <p v-if="error" role="alert" class="mt-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
          {{ error }}
        </p>

        <div class="mt-6 grid gap-x-10 gap-y-8 lg:grid-cols-[minmax(0,1fr)_18rem]">
          <div class="min-w-0 space-y-6">
            <!-- Short facts pair up; prose gets a row to itself. -->
            <div class="grid gap-x-6 gap-y-4 sm:grid-cols-2">
              <div
                v-for="field in gridFields"
                :key="field.key"
                :class="field.kind === 'multiline' ? 'sm:col-span-2' : ''"
              >
                <label :for="`field-${field.key}`" class="mb-1 block text-body-sm font-medium text-gray-700">
                  {{ field.label }}
                </label>
                <textarea
                  v-if="field.kind === 'multiline'"
                  :id="`field-${field.key}`"
                  v-model="form.data[field.key]"
                  rows="3"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
                ></textarea>
                <input
                  v-else
                  :id="`field-${field.key}`"
                  v-model="form.data[field.key]"
                  :type="inputType(field)"
                  :inputmode="field.kind === 'url' ? 'url' : undefined"
                  :placeholder="field.kind === 'url' ? 'netflix.com' : undefined"
                  :class="[
                    'w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500',
                    ['reference', 'number'].includes(field.kind) ? 'font-mono' : '',
                  ]"
                />
                <p v-if="field.hint" class="mt-1 text-caption text-gray-500">{{ field.hint }}</p>
              </div>
            </div>

            <!-- Encrypted, and it looks it. -->
            <fieldset v-if="secretFields.length" class="rounded-base border border-gray-200 bg-gray-50 p-4">
              <legend class="px-1 text-body-sm font-medium text-gray-700">
                <i class="fas fa-lock mr-1.5 text-gray-400" aria-hidden="true"></i>
                {{ secretFields.length === 1 ? secretFields[0].label : "Passwords" }}
              </legend>
              <p class="mb-3 text-caption text-gray-500">
                Encrypted with your private section passphrase. You'll be asked to unlock when you save.
              </p>
              <div class="space-y-4">
                <RecordSecretInput
                  v-for="field in secretFields"
                  :key="field.key"
                  :field="field"
                  v-model="form.secrets[field.key]"
                />
              </div>
            </fieldset>
          </div>

          <aside class="space-y-8 lg:border-l lg:border-gray-200 lg:pl-8">
            <div v-if="!isCompactForm">
              <h2 class="mb-3 text-caption uppercase tracking-wider text-gray-500">Documents</h2>
              <RecordAttachmentPicker v-model="attachmentIds" :visibility="form.visibility" />
            </div>

            <div>
              <label for="record-visibility" class="mb-2 block text-caption uppercase tracking-wider text-gray-500">
                Who can see it
              </label>
              <select
                id="record-visibility"
                v-model="form.visibility"
                class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
              >
                <option value="private">Just me</option>
                <option value="family">My family</option>
              </select>
            </div>
          </aside>
        </div>
      </form>
    </template>
  </section>
</template>
