<script setup>
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import api from "@/api/client";
import { useAuthStore } from "@/stores/auth";

const router = useRouter();
const auth = useAuthStore();

// Two steps: name the family, then invite people. Invites need the family to
// exist first, so they cannot be combined.
const step = ref(auth.family ? 2 : 1);
const familyName = ref(auth.family?.name ?? "");
const description = ref("");
const saving = ref(false);
const formError = ref("");
const fieldErrors = ref({});

const invites = ref([{ email: "", role: "editor" }]);
const sentInvites = ref([]);

const ROLES = [
  { value: "admin", label: "Admin", hint: "Can invite people and manage the family" },
  { value: "editor", label: "Editor", hint: "Can upload and edit shared files" },
  { value: "viewer", label: "Viewer", hint: "Can view shared files only" },
];

const canContinue = computed(() => familyName.value.trim().length > 0 && !saving.value);

async function createFamily() {
  formError.value = "";
  fieldErrors.value = {};
  saving.value = true;

  try {
    const { data } = await api.post("/families", {
      family: { name: familyName.value.trim(), description: description.value.trim() },
    });

    // Keep the store in step so the sidebar and permission helpers are correct.
    auth.family = { id: data.family.id, name: data.family.name, role: data.family.role };
    step.value = 2;
  } catch (error) {
    formError.value = error.userMessage;
    fieldErrors.value = error.fieldErrors ?? {};
  } finally {
    saving.value = false;
  }
}

function addInviteRow() {
  invites.value.push({ email: "", role: "editor" });
}

function removeInviteRow(index) {
  invites.value.splice(index, 1);
}

async function sendInvites() {
  formError.value = "";
  saving.value = true;

  const pending = invites.value.filter((invite) => invite.email.trim());

  for (const invite of pending) {
    try {
      await api.post(`/families/${auth.family.id}/invitations`, {
        email: invite.email.trim(),
        role: invite.role,
      });
      sentInvites.value.push(invite.email.trim());
    } catch (error) {
      // Report the first failure but keep the rest of the list intact so the
      // user doesn't have to retype everything.
      formError.value = `${invite.email}: ${error.userMessage}`;
    }
  }

  invites.value = invites.value.filter(
    (invite) => invite.email.trim() && !sentInvites.value.includes(invite.email.trim()),
  );
  if (invites.value.length === 0) invites.value = [{ email: "", role: "editor" }];

  saving.value = false;
}

function finish() {
  router.push({ name: "dashboard" });
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-gray-50 p-4">
    <div class="w-full max-w-lg">
      <div class="mb-6 text-center">
        <div class="mb-4 inline-block rounded-lg gradient-main p-3">
          <i class="fas fa-users text-2xl text-white" aria-hidden="true"></i>
        </div>
        <h1 class="text-h1 font-bold text-gray-800">
          {{ step === 1 ? "Set Up Your Family" : "Invite Your Family" }}
        </h1>
        <p class="mt-2 text-body text-gray-500">
          {{
            step === 1
              ? "Give your shared vault a name. You can change it later."
              : "Send invitations now, or skip and do it from Settings."
          }}
        </p>
      </div>

      <!-- Progress. aria-current marks the active step for screen readers. -->
      <ol class="mb-6 flex items-center justify-center gap-2" aria-label="Setup progress">
        <li
          v-for="n in 2"
          :key="n"
          :aria-current="step === n ? 'step' : undefined"
          :class="[
            'h-2 w-16 rounded-full',
            step >= n ? 'bg-primary-600' : 'bg-gray-200',
          ]"
        >
          <span class="sr-only">Step {{ n }}{{ step === n ? " (current)" : "" }}</span>
        </li>
      </ol>

      <div class="rounded-xl bg-white p-8 shadow-lg">
        <p
          v-if="formError"
          role="alert"
          class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600"
        >
          {{ formError }}
        </p>

        <!-- Step 1 -->
        <form v-if="step === 1" class="space-y-5" novalidate @submit.prevent="createFamily">
          <div>
            <label for="family-name" class="mb-2 block text-body-sm font-medium text-gray-700">
              Family name
            </label>
            <input
              id="family-name"
              v-model="familyName"
              type="text"
              required
              placeholder="The Smith Family"
              :aria-invalid="Boolean(fieldErrors.name)"
              class="w-full rounded-base border border-gray-300 px-4 py-2 outline-none focus:border-transparent focus:ring-2 focus:ring-primary-500"
            />
            <p v-if="fieldErrors.name" class="mt-1 text-caption text-error-600">
              {{ fieldErrors.name }}
            </p>
          </div>

          <div>
            <label for="family-description" class="mb-2 block text-body-sm font-medium text-gray-700">
              Description <span class="font-normal text-gray-400">(optional)</span>
            </label>
            <textarea
              id="family-description"
              v-model="description"
              rows="2"
              placeholder="Documents and photos we all share"
              class="w-full rounded-base border border-gray-300 px-4 py-2 outline-none focus:border-transparent focus:ring-2 focus:ring-primary-500"
            ></textarea>
          </div>

          <button
            type="submit"
            :disabled="!canContinue"
            class="w-full rounded-base gradient-main py-2 font-semibold text-white transition hover:opacity-95 disabled:cursor-not-allowed disabled:opacity-60"
          >
            <span v-if="saving">
              <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Creating…
            </span>
            <span v-else>Continue</span>
          </button>
        </form>

        <!-- Step 2 -->
        <form v-else class="space-y-5" novalidate @submit.prevent="sendInvites">
          <ul v-if="sentInvites.length" class="rounded-base bg-success-50 px-4 py-3" aria-live="polite">
            <li v-for="email in sentInvites" :key="email" class="text-body-sm text-success-700">
              <i class="fas fa-check mr-2" aria-hidden="true"></i>Invitation sent to {{ email }}
            </li>
          </ul>

          <div v-for="(invite, index) in invites" :key="index" class="flex items-end gap-2">
            <div class="flex-1">
              <label :for="`invite-email-${index}`" class="mb-2 block text-body-sm font-medium text-gray-700">
                Email address
              </label>
              <input
                :id="`invite-email-${index}`"
                v-model="invite.email"
                type="email"
                placeholder="mum@smith.com"
                class="w-full rounded-base border border-gray-300 px-4 py-2 outline-none focus:border-transparent focus:ring-2 focus:ring-primary-500"
              />
            </div>

            <div>
              <label :for="`invite-role-${index}`" class="mb-2 block text-body-sm font-medium text-gray-700">
                Role
              </label>
              <select
                :id="`invite-role-${index}`"
                v-model="invite.role"
                class="rounded-base border border-gray-300 px-3 py-2 outline-none focus:ring-2 focus:ring-primary-500"
              >
                <option v-for="role in ROLES" :key="role.value" :value="role.value">
                  {{ role.label }}
                </option>
              </select>
            </div>

            <button
              v-if="invites.length > 1"
              type="button"
              class="mb-1 rounded-md p-2 text-gray-400 hover:bg-gray-100 hover:text-error-600"
              :aria-label="`Remove invitation ${index + 1}`"
              @click="removeInviteRow(index)"
            >
              <i class="fas fa-xmark" aria-hidden="true"></i>
            </button>
          </div>

          <button
            type="button"
            class="text-body-sm font-medium text-primary-600 hover:text-primary-700"
            @click="addInviteRow"
          >
            <i class="fas fa-plus mr-1" aria-hidden="true"></i>Add another
          </button>

          <dl class="rounded-base bg-gray-50 p-4 text-caption text-gray-600">
            <template v-for="role in ROLES" :key="role.value">
              <dt class="font-medium text-gray-700">{{ role.label }}</dt>
              <dd class="mb-2 last:mb-0">{{ role.hint }}</dd>
            </template>
          </dl>

          <div class="flex gap-3">
            <button
              type="button"
              class="flex-1 rounded-base border border-gray-300 py-2 font-medium text-gray-700 transition hover:bg-gray-50"
              @click="finish"
            >
              Skip for now
            </button>
            <button
              type="submit"
              :disabled="saving"
              class="flex-1 rounded-base gradient-main py-2 font-semibold text-white transition hover:opacity-95 disabled:opacity-60"
            >
              <span v-if="saving">
                <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Sending…
              </span>
              <span v-else>Send invitations</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
