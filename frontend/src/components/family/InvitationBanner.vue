<script setup>
import { onMounted, ref } from "vue";
import api from "@/api/client";
import { useAuthStore } from "@/stores/auth";
import { useToast } from "@/composables/useToast";

/**
 * Families waiting for an answer from whoever is signed in.
 *
 * An invitation to somebody who already has an account used to exist only as a
 * link in an email. If they never opened it, or lost it, nothing in the app
 * knew they had been asked — so this is where being asked becomes visible.
 */
const auth = useAuthStore();
const toast = useToast();

const invitations = ref([]);
const busy = ref(null);
const error = ref("");

const ROLE_MEANS = {
  admin: "invite people and manage the family",
  editor: "add and change what the family shares",
  viewer: "see what the family shares",
};

onMounted(load);

async function load() {
  try {
    const { data } = await api.get("/invitations/mine");
    invitations.value = data.invitations;
  } catch {
    // Nothing waiting is the ordinary case; a failure here must not take the
    // page down with it.
  }
}

async function accept(invitation) {
  busy.value = invitation.id;
  error.value = "";

  try {
    const { data } = await api.post(`/invitations/mine/${invitation.id}/accept`);
    invitations.value = invitations.value.filter((i) => i.id !== invitation.id);
    toast.show({ message: `You're in ${data.family.name}` });
    // The family you have just joined is the one you meant to be working in,
    // and the whole app reads that from the session.
    await auth.restoreSession();
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    busy.value = null;
  }
}

async function decline(invitation) {
  busy.value = invitation.id;
  error.value = "";

  try {
    await api.post(`/invitations/mine/${invitation.id}/decline`);
    invitations.value = invitations.value.filter((i) => i.id !== invitation.id);
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    busy.value = null;
  }
}
</script>

<template>
  <section v-if="invitations.length" class="mb-6 space-y-3">
    <div
      v-for="invitation in invitations"
      :key="invitation.id"
      class="flex flex-wrap items-center gap-4 rounded-xl border border-primary-200 bg-primary-50 px-5 py-4"
    >
      <i class="fas fa-users text-xl text-primary-600" aria-hidden="true"></i>

      <div class="min-w-0 flex-1">
        <p class="text-body font-medium text-gray-800">
          {{ invitation.invited_by }} invited you to {{ invitation.family.name }}
        </p>
        <p class="mt-0.5 text-body-sm text-gray-600">
          You'd be able to {{ ROLE_MEANS[invitation.role] ?? "see what the family shares" }}.
          Your own files stay yours.
        </p>
      </div>

      <div class="flex shrink-0 items-center gap-2">
        <button
          type="button"
          :disabled="busy === invitation.id"
          class="rounded-base px-3 py-2 text-body-sm font-medium text-gray-600 transition hover:bg-white disabled:opacity-60"
          @click="decline(invitation)"
        >
          No thanks
        </button>
        <button
          type="button"
          :disabled="busy === invitation.id"
          class="rounded-base bg-primary-600 px-4 py-2 text-body-sm font-semibold text-white transition hover:bg-primary-700 disabled:opacity-60"
          @click="accept(invitation)"
        >
          {{ busy === invitation.id ? "Joining…" : "Join" }}
        </button>
      </div>
    </div>

    <p v-if="error" role="alert" class="rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
      {{ error }}
    </p>
  </section>
</template>
