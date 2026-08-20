<script setup>
import { computed, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import { runtimeConfig } from "@/api/client";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();

const email = ref("");
const password = ref("");
const rememberMe = ref(false);
const formError = ref("");
const fieldErrors = ref({});

// The session expired while the user was away (router adds ?expired=1).
const expired = computed(() => route.query.expired === "1");

// OAuth buttons only appear when the API is actually configured for them.
const oauthEnabled = computed(() => Boolean(runtimeConfig.oauthProviders?.length));

async function handleSubmit() {
  formError.value = "";
  fieldErrors.value = {};

  try {
    await auth.login(email.value, password.value, rememberMe.value);
    const redirect = typeof route.query.redirect === "string" ? route.query.redirect : null;
    // Where they were headed wins: an invitation link is itself the way out of
    // having no family, so diverting to setup would defeat it.
    if (redirect) return router.push(redirect);

    router.push(auth.needsFamilySetup ? { name: "family-setup" } : { name: "dashboard" });
  } catch (error) {
    formError.value = error.userMessage;
    fieldErrors.value = error.fieldErrors ?? {};
  }
}
</script>

<template>
  <div
    class="flex min-h-screen items-center justify-center bg-gradient-to-br from-primary-600 via-secondary-600 to-accent-500 p-4"
  >
    <div class="w-full max-w-md">
      <!-- Brand -->
      <div class="mb-8 text-center">
        <div class="mb-4 inline-block rounded-lg bg-white p-3">
          <i class="fas fa-cloud text-3xl text-primary-600" aria-hidden="true"></i>
        </div>
        <h1 class="text-3xl font-bold text-white">CloudVault</h1>
        <p class="mt-2 text-primary-100">Secure Family Cloud Storage</p>
      </div>

      <form
        class="space-y-6 rounded-xl bg-white p-8 shadow-2xl"
        novalidate
        @submit.prevent="handleSubmit"
      >
        <!-- role="alert" so screen readers announce failures without a focus move -->
        <p
          v-if="expired"
          role="status"
          class="rounded-base bg-warning-50 px-4 py-3 text-body-sm text-warning-600"
        >
          Your session expired. Please sign in again.
        </p>

        <p
          v-if="formError"
          role="alert"
          class="rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
        >
          {{ formError }}
        </p>

        <div>
          <label for="email" class="mb-2 block text-body-sm font-medium text-gray-700">
            Email Address
          </label>
          <input
            id="email"
            v-model="email"
            type="email"
            name="email"
            autocomplete="email"
            required
            placeholder="you@example.com"
            :aria-invalid="Boolean(fieldErrors.email)"
            :aria-describedby="fieldErrors.email ? 'email-error' : undefined"
            class="w-full rounded-base border border-gray-300 px-4 py-2 outline-none focus:border-transparent focus:ring-2 focus:ring-primary-500"
          />
          <p v-if="fieldErrors.email" id="email-error" class="mt-1 text-caption text-error-600">
            {{ fieldErrors.email }}
          </p>
        </div>

        <div>
          <label for="password" class="mb-2 block text-body-sm font-medium text-gray-700">
            Password
          </label>
          <input
            id="password"
            v-model="password"
            type="password"
            name="password"
            autocomplete="current-password"
            required
            placeholder="••••••••"
            :aria-invalid="Boolean(fieldErrors.password)"
            :aria-describedby="fieldErrors.password ? 'password-error' : undefined"
            class="w-full rounded-base border border-gray-300 px-4 py-2 outline-none focus:border-transparent focus:ring-2 focus:ring-primary-500"
          />
          <p v-if="fieldErrors.password" id="password-error" class="mt-1 text-caption text-error-600">
            {{ fieldErrors.password }}
          </p>
        </div>

        <div class="flex items-center justify-between text-body-sm">
          <label class="flex items-center">
            <input
              v-model="rememberMe"
              type="checkbox"
              class="rounded border-gray-300 text-primary-600 focus:ring-primary-500"
            />
            <span class="ml-2 text-gray-700">Remember me</span>
          </label>
          <RouterLink
            :to="{ name: 'login' }"
            class="font-medium text-primary-600 hover:text-primary-700"
          >
            Forgot password?
          </RouterLink>
        </div>

        <button
          type="submit"
          :disabled="auth.loading"
          class="w-full rounded-base bg-gradient-to-r from-primary-600 to-secondary-600 py-2 font-semibold text-white transition hover:from-primary-700 hover:to-secondary-700 disabled:cursor-not-allowed disabled:opacity-60"
        >
          <span v-if="auth.loading">
            <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Signing in…
          </span>
          <span v-else>Sign In</span>
        </button>

        <template v-if="oauthEnabled">
          <div class="relative">
            <div class="absolute inset-0 flex items-center">
              <div class="w-full border-t border-gray-300"></div>
            </div>
            <div class="relative flex justify-center text-body-sm">
              <span class="bg-white px-2 text-gray-500">Or continue with</span>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <a
              :href="`${runtimeConfig.apiUrl}/api/v1/auth/google`"
              class="flex items-center justify-center rounded-base border border-gray-300 py-2 transition hover:bg-gray-50"
            >
              <i class="fab fa-google mr-2 text-error-500" aria-hidden="true"></i>
              <span class="text-body-sm font-medium text-gray-700">Google</span>
            </a>
            <a
              :href="`${runtimeConfig.apiUrl}/api/v1/auth/github`"
              class="flex items-center justify-center rounded-base border border-gray-300 py-2 transition hover:bg-gray-50"
            >
              <i class="fab fa-github mr-2 text-gray-700" aria-hidden="true"></i>
              <span class="text-body-sm font-medium text-gray-700">GitHub</span>
            </a>
          </div>
        </template>

        <p class="text-center text-body-sm text-gray-600">
          Don't have an account?
          <RouterLink
            :to="{ name: 'register' }"
            class="font-medium text-primary-600 hover:text-primary-700"
          >
            Sign up
          </RouterLink>
        </p>
      </form>
    </div>
  </div>
</template>
