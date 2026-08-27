<script setup>
import { computed, onMounted, ref } from "vue";
import api from "@/api/client";
import RecordBreadcrumb from "@/components/records/RecordBreadcrumb.vue";
import { recordTypeAccent, recordTypeTint } from "@/utils/recordType";

const templates = ref([]);
const loading = ref(true);
const error = ref("");
const search = ref("");

const breadcrumbs = [
  { label: "Register", to: { name: "household-register" } },
  { label: "Add" },
];

const matches = computed(() => {
  const term = search.value.trim().toLowerCase();
  if (!term) return templates.value;

  return templates.value.filter((t) =>
    [t.label, t.summary, t.title_hint, ...t.fields.map((f) => f.label)]
      .filter(Boolean)
      .join(" ")
      .toLowerCase()
      .includes(term),
  );
});

/** Whether this kind of thing keeps a password, which decides where it lives. */
function holdsSecrets(template) {
  return template.fields.some((f) => f.kind === "secret");
}

/** The dates this kind of thing watches — the reason to file it at all. */
function watches(template) {
  return template.fields.filter((f) => f.kind === "expiry").map((f) => f.label);
}

onMounted(async () => {
  try {
    const { data } = await api.get("/record_templates");
    templates.value = data.templates;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <section class="mx-auto max-w-5xl">
    <RecordBreadcrumb :crumbs="breadcrumbs" />

    <header class="border-b border-gray-200 pb-5">
      <h1 class="text-h2 font-bold text-gray-800">What are you filing?</h1>
      <p class="mt-1 text-body-sm text-gray-500">
        Each one starts with the fields that kind of thing usually has. You can add your own.
      </p>
    </header>

    <p v-if="error" role="alert" class="mt-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
      {{ error }}
    </p>

    <div class="mt-5">
      <label for="type-search" class="sr-only">Search the kinds of record</label>
      <div class="relative max-w-sm">
        <i
          class="fas fa-magnifying-glass pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-gray-400"
          aria-hidden="true"
        ></i>
        <input
          id="type-search"
          v-model="search"
          type="search"
          placeholder="passport, meter, insurance…"
          class="w-full rounded-base border border-gray-300 py-2 pl-9 pr-3 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
        />
      </div>
    </div>

    <div v-if="loading" class="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <div v-for="n in 9" :key="n" class="h-32 animate-pulse rounded-lg bg-gray-100"></div>
    </div>

    <p v-else-if="!matches.length" class="mt-8 text-center text-body-sm text-gray-500">
      Nothing matches that. Pick the closest kind — every record takes fields you name yourself.
    </p>

    <ul v-else class="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <li v-for="template in matches" :key="template.type">
        <RouterLink
          :to="{ name: 'record-create', params: { type: template.type } }"
          class="group flex h-full flex-col rounded-lg border border-gray-200 bg-white p-4 transition hover:-translate-y-0.5 hover:border-gray-300 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
          :style="{ '--accent': recordTypeAccent(template.type) }"
        >
          <span class="mb-3 flex items-start gap-3">
            <span
              class="flex h-10 w-10 shrink-0 items-center justify-center rounded-base"
              :style="{ backgroundColor: recordTypeTint(template.type), color: recordTypeAccent(template.type) }"
            >
              <i :class="['fas', template.icon]" aria-hidden="true"></i>
            </span>
            <span class="min-w-0 flex-1">
              <span class="block text-body font-semibold text-gray-800">{{ template.label }}</span>
              <span class="mt-0.5 block text-body-sm leading-snug text-gray-500">
                {{ template.summary }}
              </span>
            </span>
            <i
              class="fas fa-lock mt-1 text-caption text-gray-300"
              :title="'Keeps a password'"
              aria-hidden="true"
              v-if="holdsSecrets(template)"
            ></i>
          </span>

          <!-- What this kind of thing watches. The reason to file it at all. -->
          <span
            v-if="watches(template).length"
            class="mt-auto flex flex-wrap items-center gap-1.5 border-t border-gray-100 pt-3"
          >
            <i class="fas fa-bell text-caption text-gray-300" aria-hidden="true"></i>
            <span
              v-for="label in watches(template)"
              :key="label"
              class="rounded-full bg-gray-50 px-2 py-0.5 text-caption text-gray-600"
            >
              {{ label }}
            </span>
          </span>
          <span v-else class="mt-auto border-t border-gray-100 pt-3 text-caption text-gray-400">
            e.g. {{ template.title_hint }}
          </span>
        </RouterLink>
      </li>
    </ul>
  </section>
</template>
