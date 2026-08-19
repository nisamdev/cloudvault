<script setup>
import { computed, onMounted, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import api from "@/api/client";
import { useAuthStore } from "@/stores/auth";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();

const invitation = ref(null);
const loading = ref(true);
const accepting = ref(false);
const error = ref("");

const token = computed(() => route.params.token);

// The invitation is addressed to one mailbox; the API rejects acceptance from
// any other account, so say so before the user tries.
const wrongAccount = computed(
  () => auth.isAuthenticated && invitation.value && auth.user.email !== invitation.value.email,
);

onMounted(async () => {
  try {
    const { data } = await api.get(`/invitations/${token.value}`);
    invitation.value = data.invitation;
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
});

async function accept() {
  accepting.value = true;
  error.value = "";

  try {
    await api.post(`/invitations/${token.value}/accept`);
    // Refresh the session so the new family and role are in the store.
    await auth.restoreSession();
    router.push({ name: "dashboard" });
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    accepting.value = false;
  }
}

function signIn() {
  router.push({ name: "login", query: { redirect: route.fullPath } });
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-gray-50 p-4">
    <div class="w-full max-w-md rounded-xl bg-white p-8 text-center shadow-lg">
      <div v-if="loading" class="py-8">
        <i class="fas fa-circle-notch fa-spin text-2xl text-gray-400" aria-hidden="true"></i>
        <p class="mt-3 text-body text-gray-500">Checking your invitation…</p>
      </div>

      <template v-else-if="invitation">
        <div class="mb-4 inline-block rounded-lg gradient-main p-3">
          <i class="fas fa-users text-2xl text-white" aria-hidden="true"></i>
        </div>

        <h1 class="text-h2 font-bold text-gray-800">
          Join {{ invitation.family_name }}
        </h1>
        <p class="mt-2 text-body text-gray-600">
          {{ invitation.invited_by }} invited
          <strong>{{ invitation.email }}</strong>
          to join as <strong>{{ invitation.role }}</strong>.
        </p>

        <p
          v-if="error"
          role="alert"
          class="mt-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
        >
          {{ error }}
        </p>

        <p
          v-if="wrongAccount"
          class="mt-4 rounded-base bg-warning-50 px-4 py-3 text-body-sm text-warning-600"
        >
          You're signed in as {{ auth.user.email }}. Sign in as
          {{ invitation.email }} to accept this invitation.
        </p>

        <div class="mt-6">
          <button
            v-if="auth.isAuthenticated && !wrongAccount"
            type="button"
            :disabled="accepting"
            class="w-full rounded-base gradient-main py-2 font-semibold text-white transition hover:opacity-95 disabled:opacity-60"
            @click="accept"
          >
            <span v-if="accepting">
              <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Joining…
            </span>
            <span v-else>Accept invitation</span>
          </button>

          <button
            v-else
            type="button"
            class="w-full rounded-base gradient-main py-2 font-semibold text-white transition hover:opacity-95"
            @click="signIn"
          >
            Sign in to accept
          </button>

          <RouterLink
            v-if="!auth.isAuthenticated"
            :to="{ name: 'register' }"
            class="mt-3 block text-body-sm font-medium text-primary-600 hover:text-primary-700"
          >
            Don't have an account? Create one
          </RouterLink>
        </div>
      </template>

      <template v-else>
        <i class="fas fa-link-slash text-4xl text-gray-300" aria-hidden="true"></i>
        <h1 class="mt-4 text-h2 font-bold text-gray-800">Invitation not valid</h1>
        <p class="mt-2 text-body text-gray-600">
          {{ error || "This invitation has expired or has already been used." }}
        </p>
        <RouterLink
          :to="{ name: 'login' }"
          class="mt-6 inline-block rounded-base gradient-main px-6 py-2 font-semibold text-white"
        >
          Go to sign in
        </RouterLink>
      </template>
    </div>
  </div>
</template>
