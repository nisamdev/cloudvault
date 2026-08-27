<script setup>
import { computed, onMounted, ref, watch } from "vue";
import { useRouter } from "vue-router";
import api from "@/api/client";
import RecordIcon from "@/components/records/RecordIcon.vue";
import ScanModal from "@/components/files/ScanModal.vue";
import { siteDomain } from "@/utils/recordIcon";
import { recordTypeAccent, recordTypeTint } from "@/utils/recordType";
import { expiryState, formatRecordDate } from "@/utils/recordDate";
import { sectionFor } from "@/utils/recordSection";

/** "people" — a person's documents; "household" — the house's affairs. */
const props = defineProps({
  group: { type: String, default: "people" },
});

const allRecords = ref([]);
const templates = ref([]);
const loading = ref(true);
const error = ref("");
const search = ref("");
const typeFilter = ref("");
const holderFilter = ref("");
const scanning = ref(false);

const section = computed(() => sectionFor(props.group));

/** The kinds that live in this half, in the order the templates declare them. */
const kinds = computed(() => templates.value.filter((t) => t.group === props.group));
const kindTypes = computed(() => new Set(kinds.value.map((t) => t.type)));

/** Everything in this half, before the filters on screen narrow it. */
const records = computed(() => allRecords.value.filter((r) => kindTypes.value.has(r.record_type)));

/** How many of each kind, so a filter can say what it would leave you. */
const countByType = computed(() =>
  records.value.reduce((counts, record) => {
    counts[record.record_type] = (counts[record.record_type] ?? 0) + 1;
    return counts;
  }, {}),
);

/** Only offer a filter for a kind there is something to filter. */
const kindsPresent = computed(() => kinds.value.filter((t) => countByType.value[t.type]));

/**
 * Whose documents these are — built from the records themselves rather than
 * from the family, so somebody with no login still appears the moment they
 * hold something.
 */
const holders = computed(() => {
  const found = new Map();
  for (const record of records.value) {
    if (record.held_by) found.set(record.held_by.id, record.held_by);
  }

  return [...found.values()].sort((a, b) => a.name.localeCompare(b.name));
});

const filtered = computed(() => {
  const term = search.value.trim().toLowerCase();
  return records.value.filter((record) => {
    if (typeFilter.value && record.record_type !== typeFilter.value) return false;
    if (holderFilter.value && String(record.held_by?.id ?? "") !== holderFilter.value) return false;
    if (!term) return true;
    const haystack = [
      record.title,
      record.type_label,
      record.website,
      record.held_by?.name,
      ...(record.highlights ?? []).map((h) => h.value),
    ]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();
    return haystack.includes(term);
  });
});

const anyFilter = computed(() => Boolean(typeFilter.value || holderFilter.value || search.value));

function clearFilters() {
  typeFilter.value = "";
  holderFilter.value = "";
  search.value = "";
}

/** Clicking the kind you are already filtered to takes the filter off again. */
function toggleType(type) {
  typeFilter.value = typeFilter.value === type ? "" : type;
}

const router = useRouter();

/**
 * The phone has photographed a document and left the pages waiting. Open the
 * form it belongs to and carry the scan across: the trimming, the reading and
 * the checking all happen there, on a screen big enough to do them properly.
 */
function onScanned(receipt) {
  scanning.value = false;

  if (!receipt?.pages?.length) {
    load();
    return;
  }

  router.push({
    name: "record-create",
    params: { type: receipt.record_type || "other" },
    query: { scan: receipt.token },
  });
}

// The same component serves both halves, so moving between them must not carry
// a filter across into a list where it means nothing.
watch(() => props.group, clearFilters);

onMounted(load);

async function load() {
  loading.value = true;
  error.value = "";
  try {
    const [recordsRes, templatesRes] = await Promise.all([
      api.get("/records"),
      api.get("/record_templates"),
    ]);
    allRecords.value = recordsRes.data.records;
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

  // The badge below already says what kind of thing this is. Repeating it
  // here just fills the line with the same word twice.
  return "";
}
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-h2 font-bold text-gray-800">{{ section.label }}</h1>
        <p v-if="!loading" class="mt-1 text-body-sm text-gray-500">
          <template v-if="records.length">
            {{ records.length }} {{ records.length === 1 ? "record" : "records" }}
            <template v-if="holders.length">
              · {{ holders.length }} {{ holders.length === 1 ? "person" : "people" }}
            </template>
          </template>
          <template v-else-if="group === 'people'">
            Passports, licences and certificates, filed under whose they are.
          </template>
          <template v-else>The house's accounts, property and money.</template>
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          v-if="group === 'people'"
          type="button"
          class="rounded-base border border-gray-300 bg-white px-4 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
          @click="scanning = true"
        >
          <i class="fas fa-qrcode mr-1.5" aria-hidden="true"></i>
          Scan a document
        </button>
        <RouterLink
          v-else
          :to="{ name: 'record-create', params: { type: 'login' } }"
          class="rounded-base border border-primary-200 bg-primary-50 px-4 py-2 text-body-sm font-medium text-primary-700 transition hover:bg-primary-100"
        >
          <i class="fas fa-key mr-1.5" aria-hidden="true"></i>
          Add login
        </RouterLink>
        <RouterLink
          :to="{ name: 'record-new', query: { group } }"
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
        v-if="holders.length"
        v-model="holderFilter"
        aria-label="Filter by whose it is"
        class="rounded-base border border-gray-300 px-3 py-2.5 text-body-sm outline-none focus:ring-2 focus:ring-primary-500 sm:w-52"
      >
        <option value="">Anyone's</option>
        <option v-for="holder in holders" :key="holder.id" :value="String(holder.id)">
          {{ holder.name }}
        </option>
      </select>
    </div>

    <!-- The kinds, as the icons the cards carry. Reading a row of icons is
         quicker than reading a dropdown, and it doubles as a count of what is
         actually filed. -->
    <div v-if="kindsPresent.length > 1" class="mb-5 flex flex-wrap items-center gap-2">
      <button
        v-for="kind in kindsPresent"
        :key="kind.type"
        type="button"
        :aria-pressed="typeFilter === kind.type"
        :title="kind.label"
        :class="[
          'flex items-center gap-2 rounded-full border px-3 py-1.5 text-body-sm font-medium transition',
          typeFilter === kind.type
            ? 'border-transparent shadow-sm'
            : 'border-gray-200 bg-white text-gray-600 hover:border-gray-300',
        ]"
        :style="
          typeFilter === kind.type
            ? { backgroundColor: recordTypeTint(kind.type), color: recordTypeAccent(kind.type) }
            : {}
        "
        @click="toggleType(kind.type)"
      >
        <i
          :class="['fas', kind.icon]"
          :style="{ color: recordTypeAccent(kind.type) }"
          aria-hidden="true"
        ></i>
        {{ kind.label }}
        <span class="tabular-nums opacity-60">{{ countByType[kind.type] }}</span>
      </button>

      <button
        v-if="anyFilter"
        type="button"
        class="rounded-full px-3 py-1.5 text-body-sm font-medium text-gray-500 underline transition hover:text-gray-700"
        @click="clearFilters"
      >
        Clear
      </button>
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
              :record-type="record.record_type"
              :fallback="record.record_type === 'person' ? 'initials' : 'kind'"
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
            <!-- The icon already says what kind of thing this is, so the
                 badge says whose it is instead — the more useful half of
                 "Aisha's passport" once a house holds four of them. -->
            <span
              v-if="record.held_by"
              class="flex min-w-0 items-center gap-1.5 truncate text-caption font-medium text-gray-600"
            >
              <i class="fas fa-user text-gray-400" aria-hidden="true"></i>
              {{ record.held_by.name }}
            </span>
            <span
              v-else
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

    <ScanModal
      v-if="scanning"
      purpose="record"
      @uploaded="onScanned"
      @close="scanning = false"
    />
  </section>
</template>
