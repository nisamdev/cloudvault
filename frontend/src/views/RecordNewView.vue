<script setup>
import { onMounted, ref } from "vue";
import api from "@/api/client";
import RecordBreadcrumb from "@/components/records/RecordBreadcrumb.vue";

const templates = ref([]);
const loading = ref(true);
const error = ref("");

const breadcrumbs = [
  { label: "Register", to: { name: "household-register" } },
  { label: "Add" },
];

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
  <section class="mx-auto max-w-3xl">
    <RecordBreadcrumb :crumbs="breadcrumbs" />

    <header class="mb-6">
      <h1 class="text-h2 font-bold text-gray-800">Add a record</h1>
    </header>

    <p v-if="error" role="alert" class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
      {{ error }}
    </p>

    <div v-if="loading" class="grid gap-2 sm:grid-cols-2">
      <div v-for="n in 6" :key="n" class="h-12 animate-pulse rounded-base bg-gray-100"></div>
    </div>

    <ul v-else class="divide-y divide-gray-200 rounded-lg border border-gray-200 bg-white">
      <li v-for="template in templates" :key="template.type">
        <RouterLink
          :to="{ name: 'record-create', params: { type: template.type } }"
          class="flex items-center gap-3 px-4 py-3 transition hover:bg-gray-50"
        >
          <i :class="['fas w-5 text-center text-gray-400', template.icon]" aria-hidden="true"></i>
          <span class="flex-1 text-body font-medium text-gray-800">{{ template.label }}</span>
          <i class="fas fa-chevron-right text-gray-300" aria-hidden="true"></i>
        </RouterLink>
      </li>
    </ul>
  </section>
</template>
