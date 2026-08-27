<script setup>
import { computed, onMounted, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import api from "@/api/client";
import RecordAttachmentPicker from "@/components/records/RecordAttachmentPicker.vue";
import RecordBreadcrumb from "@/components/records/RecordBreadcrumb.vue";
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
  <section class="mx-auto max-w-xl">
    <RecordBreadcrumb :crumbs="breadcrumbs" />

    <div v-if="loading" class="space-y-4">
      <div class="h-8 w-40 animate-pulse rounded-base bg-gray-100"></div>
      <div class="h-48 animate-pulse rounded-base bg-gray-100"></div>
    </div>

    <template v-else-if="template">
      <header class="mb-6">
        <h1 class="text-h2 font-bold text-gray-800">New {{ template.label.toLowerCase() }}</h1>
      </header>

      <p v-if="error" role="alert" class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
        {{ error }}
      </p>

      <form class="space-y-6" @submit.prevent="save">
        <fieldset class="space-y-4">
          <legend class="sr-only">{{ isCompactForm ? "Login details" : "Basic details" }}</legend>

          <div v-if="showTitleField">
            <label for="record-title" class="mb-1 block text-body-sm font-medium text-gray-700">Title</label>
            <input
              id="record-title"
              v-model="form.title"
              type="text"
              required
              autofocus
              :placeholder="template.title_hint"
              class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
            />
          </div>

          <div v-for="field in editableFields" :key="field.key">
            <label :for="`field-${field.key}`" class="mb-1 block text-body-sm font-medium text-gray-700">
              {{ field.label }}
            </label>
            <p v-if="field.hint && isCompactForm" class="mb-1 text-caption text-gray-500">{{ field.hint }}</p>
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
              :required="field.key === titleFieldKey"
              :autofocus="field.key === titleFieldKey"
              :placeholder="field.hint && !isCompactForm ? field.hint : field.kind === 'url' ? 'netflix.com' : undefined"
              class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
            />
          </div>

          <template v-if="compactSecrets && secretFields.length">
            <RecordSecretInput
              v-for="field in secretFields"
              :key="field.key"
              :field="field"
              v-model="form.secrets[field.key]"
            />
            <p class="text-caption text-gray-500">Encrypted — unlock your private section when you save.</p>
          </template>

          <div>
            <label for="record-visibility" class="mb-1 block text-body-sm font-medium text-gray-700">Who can see it</label>
            <select
              id="record-visibility"
              v-model="form.visibility"
              class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
            >
              <option value="private">Just me</option>
              <option value="family">My family</option>
            </select>
          </div>
        </fieldset>

        <fieldset v-if="secretFields.length && !compactSecrets" class="space-y-4">
          <legend class="mb-1 text-body-sm font-medium text-gray-700">Passwords</legend>
          <p class="mb-3 text-caption text-gray-500">
            Encrypted with your private section passphrase. Unlock when you save.
          </p>
          <RecordSecretInput
            v-for="field in secretFields"
            :key="field.key"
            :field="field"
            v-model="form.secrets[field.key]"
          />
        </fieldset>

        <fieldset v-if="!isCompactForm">
          <legend class="mb-3 text-body-sm font-medium text-gray-700">Documents</legend>
          <RecordAttachmentPicker v-model="attachmentIds" :visibility="form.visibility" />
        </fieldset>

        <div class="flex gap-2 pt-2">
          <button
            type="submit"
            :disabled="saving || !canSave()"
            class="rounded-base bg-primary-600 px-5 py-2 text-body-sm font-medium text-white transition hover:bg-primary-700 disabled:opacity-60"
          >
            {{ saving ? "Saving…" : "Save" }}
          </button>
          <button
            type="button"
            class="rounded-base px-4 py-2 text-body-sm font-medium text-gray-600 transition hover:text-gray-800"
            @click="router.push({ name: 'household-register' })"
          >
            Cancel
          </button>
        </div>
      </form>
    </template>
  </section>
</template>
