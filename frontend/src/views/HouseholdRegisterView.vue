<script setup>
import { computed, onMounted, ref } from "vue";
import api from "@/api/client";
import RecordIcon from "@/components/records/RecordIcon.vue";
import { siteDomain } from "@/utils/recordIcon";
import { recordTypeAccent, recordTypeTint } from "@/utils/recordType";
import { expiryState, formatRecordDate } from "@/utils/recordDate";

const records = ref([]);
const templates = ref([]);
const loading = ref(true);
const error = ref("");
const search = ref("");
const typeFilter = ref("");

const filtered = computed(() => {
  const term = search.value.trim().toLowerCase();
  return records.value.filter((record) => {
    if (typeFilter.value && record.record_type !== typeFilter.value) return false;
    if (!term) return true;
    const haystack = [
      record.title,
      record.type_label,
      record.website,
      ...(record.highlights ?? []).map((h) => h.value),
    ]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();
    return haystack.includes(term);
  });
});

const loginCount = computed(() => records.value.filter((r) => r.record_type === "login").length);

onMounted(load);

async function load() {
  loading.value = true;
  error.value = "";
  try {
    const [recordsRes, templatesRes] = await Promise.all([
      api.get("/records"),
      api.get("/record_templates"),
    ]);
    records.value = recordsRes.data.records;
    templates.value = templatesRes.data.templates;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}

/**
 * A date is written the way it would be spoken, and a reference is left in
 * monospace — the same rules the record's own page follows, so a card and the
 * page behind it do not describe the same fact two different ways.
 */
function highlightText(highlight) {
  if (["date", "expiry"].includes(highlight.kind)) return formatRecordDate(highlight.value);
  return highlight.value;
}

/** What this record is counting down to, if anything. */
function countdown(record) {
  return record.next_expiry ? expiryState(record.next_expiry.date) : null;
}

const COUNTDOWN_TONE = {
  expired: "text-error-600",
  urgent: "text-error-600",
  soon: "text-warning-600",
  fine: "text-gray-500",
};

/** One line under the title — username, domain, or a useful highlight. */
function recordSubtitle(record) {
  const highlights = (record.highlights ?? [])
    .filter((h) => h.value)
    .filter((h) => !["date", "expiry"].includes(h.kind))
    .map((h) => highlightText(h))
    .filter((v) => v !== record.title && !/^https?:\/\//i.test(v));

  if (record.record_type === "login") {
    return highlights[0] || siteDomain(record.website) || "Saved login";
  }

  if (highlights.length) return highlights.slice(0, 2).join(" · ");
  return record.type_label;
}
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-h2 font-bold text-gray-800">Register</h1>
        <p v-if="!loading && records.length" class="mt-1 text-body-sm text-gray-500">
          {{ records.length }} {{ records.length === 1 ? "record" : "records" }}
          <template v-if="loginCount"> · {{ loginCount }} {{ loginCount === 1 ? "login" : "logins" }}</template>
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <RouterLink
          :to="{ name: 'record-create', params: { type: 'login' } }"
          class="rounded-base border border-primary-200 bg-primary-50 px-4 py-2 text-body-sm font-medium text-primary-700 transition hover:bg-primary-100"
        >
          <i class="fas fa-key mr-1.5" aria-hidden="true"></i>
          Add login
        </RouterLink>
        <RouterLink
          :to="{ name: 'record-new' }"
          class="rounded-base bg-primary-600 px-4 py-2 text-body-sm font-medium text-white transition hover:bg-primary-700"
        >
          Add record
        </RouterLink>
      </div>
    </header>

    <p v-if="error" role="alert" class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
      {{ error }}
    </p>

    <div class="mb-5 flex flex-col gap-2 sm:flex-row">
      <div class="relative min-w-0 flex-1">
        <i
          class="fas fa-magnifying-glass pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-gray-400"
          aria-hidden="true"
        ></i>
        <input
          v-model="search"
          type="search"
          placeholder="Search by name, site, username…"
          aria-label="Search records"
          class="w-full rounded-base border border-gray-300 py-2.5 pl-9 pr-3 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
        />
      </div>
      <select
        v-model="typeFilter"
        aria-label="Filter by type"
        class="rounded-base border border-gray-300 px-3 py-2.5 text-body-sm outline-none focus:ring-2 focus:ring-primary-500 sm:w-48"
      >
        <option value="">All types</option>
        <option v-for="template in templates" :key="template.type" :value="template.type">
          {{ template.label }}
        </option>
      </select>
    </div>

    <div v-if="loading" class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      <div v-for="n in 8" :key="n" class="h-28 animate-pulse rounded-xl bg-gray-100"></div>
    </div>

    <div
      v-else-if="!filtered.length"
      class="rounded-xl border border-dashed border-gray-300 bg-gray-50 px-6 py-16 text-center"
    >
      <i class="fas fa-book-open mb-3 text-3xl text-gray-300" aria-hidden="true"></i>
      <p class="text-body-sm text-gray-500">
        <template v-if="records.length">Nothing matches your search.</template>
        <template v-else>
          Passwords, permits, property details — start with a login or pick a record type.
        </template>
      </p>
      <div v-if="!records.length" class="mt-4 flex flex-wrap justify-center gap-2">
        <RouterLink
          :to="{ name: 'record-create', params: { type: 'login' } }"
          class="rounded-base bg-primary-600 px-4 py-2 text-body-sm font-medium text-white hover:bg-primary-700"
        >
          Add a login
        </RouterLink>
        <RouterLink
          :to="{ name: 'record-new' }"
          class="rounded-base border border-gray-300 bg-white px-4 py-2 text-body-sm font-medium text-gray-700 hover:bg-gray-50"
        >
          Other record types
        </RouterLink>
      </div>
    </div>

    <ul v-else class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      <li v-for="record in filtered" :key="record.id">
        <RouterLink
          :to="{ name: 'record', params: { id: record.id } }"
          class="group flex h-full flex-col rounded-xl border border-gray-200 bg-white p-4 shadow-sm transition hover:-translate-y-0.5 hover:border-gray-300 hover:shadow-md"
        >
          <div class="mb-4 flex items-start gap-3">
            <RecordIcon
              :title="record.title"
              :website="record.website"
              :type-icon="record.type_icon"
              size="md"
            />
            <div class="min-w-0 flex-1 pt-0.5">
              <span class="block truncate font-semibold text-gray-900 group-hover:text-primary-700">
                {{ record.title }}
              </span>
              <span
                :class="[
                  'mt-0.5 block truncate text-body-sm text-gray-500',
                  (record.highlights ?? []).some((h) => h.kind === 'reference') ? 'font-mono' : '',
                ]"
              >
                {{ recordSubtitle(record) }}
              </span>
            </div>
          </div>

          <div class="mt-auto flex items-center justify-between gap-2 border-t border-gray-100 pt-3">
            <span
              class="truncate rounded-full px-2 py-0.5 text-caption font-medium"
              :style="{
                backgroundColor: recordTypeTint(record.record_type),
                color: recordTypeAccent(record.record_type),
              }"
            >
              {{ record.type_label }}
            </span>
            <!-- What it is counting down to beats when it was last touched:
                 nobody opens the register to find out what they edited. -->
            <span
              v-if="countdown(record)"
              :class="['shrink-0 text-caption font-medium', COUNTDOWN_TONE[countdown(record).tone]]"
              :title="`${record.next_expiry.label}: ${countdown(record).formatted}`"
            >
              {{ countdown(record).label }}
            </span>
          </div>
        </RouterLink>
      </li>
    </ul>
  </section>
</template>
