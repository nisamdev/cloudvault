<script setup>
import { computed, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();

const fullName = ref("");
// An invitation is addressed to one mailbox and the API refuses any other, so
// arriving from one prefills it rather than letting the wrong address be typed.
const email = ref(typeof route.query.email === "string" ? route.query.email : "");
const password = ref("");
const passwordConfirmation = ref("");
const acceptedTerms = ref(false);
const formError = ref("");
const fieldErrors = ref({});

// Mirrors the API's minimum; the server re-validates regardless.
const MIN_PASSWORD_LENGTH = 8;

const passwordStrength = computed(() => {
  const value = password.value;
  if (!value) return { score: 0, label: "", className: "bg-gray-200" };

  let score = 0;
  if (value.length >= MIN_PASSWORD_LENGTH) score += 1;
  if (value.length >= 12) score += 1;
  if (/[A-Z]/.test(value) && /[a-z]/.test(value)) score += 1;
  if (/\d/.test(value)) score += 1;
  if (/[^A-Za-z0-9]/.test(value)) score += 1;

  if (score <= 2) return { score, label: "Weak", className: "bg-error-500" };
  if (score <= 3) return { score, label: "Fair", className: "bg-warning-500" };
  if (score <= 4) return { score, label: "Good", className: "bg-info-500" };
  return { score, label: "Strong", className: "bg-success-500" };
});

const passwordsMatch = computed(
  () => !passwordConfirmation.value || password.value === passwordConfirmation.value,
);

const canSubmit = computed(
  () =>
    email.value &&
    password.value.length >= MIN_PASSWORD_LENGTH &&
    passwordsMatch.value &&
    acceptedTerms.value &&
    !auth.loading,
);

async function handleSubmit() {
  formError.value = "";
  fieldErrors.value = {};

  if (!passwordsMatch.value) {
    fieldErrors.value = { password_confirmation: "Passwords do not match." };
    return;
  }

  try {
    await auth.register({
      email: email.value,
      password: password.value,
      full_name: fullName.value,
      // Pre-fills the family's timezone; the user can change it in Settings.
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    });
    // Somebody who came from an invitation is about to join a family, so
    // sending them to create one first is how they end up owning an empty one
    // and being told they already belong somewhere.
    const redirect = typeof route.query.redirect === "string" ? route.query.redirect : null;
    router.push(redirect || { name: "family-setup" });
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
      <div class="mb-8 text-center">
        <div class="mb-4 inline-block rounded-lg bg-white p-3">
          <i class="fas fa-cloud text-3xl text-primary-600" aria-hidden="true"></i>
        </div>
        <h1 class="text-3xl font-bold text-white">Create your account</h1>
        <p class="mt-2 text-primary-100">Start your family vault in under a minute</p>
      </div>

      <form
        class="space-y-5 rounded-xl bg-white p-8 shadow-2xl"
        novalidate
        @submit.prevent="handleSubmit"
      >
        <p
          v-if="formError"
          role="alert"
          class="rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
        >
          {{ formError }}
        </p>

        <div>
          <label for="full-name" class="mb-2 block text-body-sm font-medium text-gray-700">
            Full name
          </label>
          <input
            id="full-name"
            v-model="fullName"
            type="text"
            autocomplete="name"
            placeholder="Dad Smith"
            class="w-full rounded-base border border-gray-300 px-4 py-2 outline-none focus:border-transparent focus:ring-2 focus:ring-primary-500"
          />
        </div>

        <div>
          <label for="email" class="mb-2 block text-body-sm font-medium text-gray-700">
            Email address
          </label>
          <input
            id="email"
            v-model="email"
            type="email"
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
            autocomplete="new-password"
            required
            :minlength="MIN_PASSWORD_LENGTH"
            placeholder="At least 8 characters"
            :aria-invalid="Boolean(fieldErrors.password)"
            :aria-describedby="fieldErrors.password ? 'password-error' : 'password-strength'"
            class="w-full rounded-base border border-gray-300 px-4 py-2 outline-none focus:border-transparent focus:ring-2 focus:ring-primary-500"
          />

          <div v-if="password" id="password-strength" class="mt-2">
            <div class="h-1 w-full overflow-hidden rounded-full bg-gray-200">
              <div
                class="h-full transition-all duration-200"
                :class="passwordStrength.className"
                :style="{ width: `${(passwordStrength.score / 5) * 100}%` }"
              ></div>
            </div>
            <!-- aria-live so the strength change is announced, not just seen -->
            <p class="mt-1 text-caption text-gray-500" aria-live="polite">
              Password strength: {{ passwordStrength.label }}
            </p>
          </div>

          <p v-if="fieldErrors.password" id="password-error" class="mt-1 text-caption text-error-600">
            {{ fieldErrors.password }}
          </p>
        </div>

        <div>
          <label for="password-confirmation" class="mb-2 block text-body-sm font-medium text-gray-700">
            Confirm password
          </label>
          <input
            id="password-confirmation"
            v-model="passwordConfirmation"
            type="password"
            autocomplete="new-password"
            required
            :aria-invalid="!passwordsMatch"
            :aria-describedby="!passwordsMatch ? 'confirmation-error' : undefined"
            class="w-full rounded-base border border-gray-300 px-4 py-2 outline-none focus:border-transparent focus:ring-2 focus:ring-primary-500"
          />
          <p
            v-if="!passwordsMatch"
            id="confirmation-error"
            role="alert"
            class="mt-1 text-caption text-error-600"
          >
            Passwords do not match.
          </p>
        </div>

        <label class="flex items-start gap-2 text-body-sm text-gray-700">
          <input
            v-model="acceptedTerms"
            type="checkbox"
            required
            class="mt-1 rounded border-gray-300 text-primary-600 focus:ring-primary-500"
          />
          <span>I agree to the Terms of Service and Privacy Policy</span>
        </label>

        <button
          type="submit"
          :disabled="!canSubmit"
          class="w-full rounded-base bg-gradient-to-r from-primary-600 to-secondary-600 py-2 font-semibold text-white transition hover:from-primary-700 hover:to-secondary-700 disabled:cursor-not-allowed disabled:opacity-60"
        >
          <span v-if="auth.loading">
            <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Creating account…
          </span>
          <span v-else>Create account</span>
        </button>

        <p class="text-center text-body-sm text-gray-600">
          Already have an account?
          <RouterLink
            :to="{ name: 'login' }"
            class="font-medium text-primary-600 hover:text-primary-700"
          >
            Sign in
          </RouterLink>
        </p>
      </form>
    </div>
  </div>
</template>
