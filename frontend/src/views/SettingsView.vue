<script setup>
import { computed, onMounted, ref } from "vue";
import api from "@/api/client";
import { useAuthStore } from "@/stores/auth";
import { useDialog } from "@/composables/useDialog";
import { useToast } from "@/composables/useToast";
import { formatFileSize, formatRelativeDate } from "@/utils/formatting";

const auth = useAuthStore();
const dialog = useDialog();
const toast = useToast();

const SECTIONS = [
  { value: "profile", label: "Profile", icon: "fa-user" },
  { value: "security", label: "Security", icon: "fa-shield-halved" },
  { value: "family", label: "Family", icon: "fa-users" },
  { value: "storage", label: "Storage", icon: "fa-hard-drive" },
];

const section = ref("profile");
const loading = ref(true);
const error = ref("");

const account = ref(null);
const storage = ref(null);
const sessions = ref([]);
const members = ref([]);
const invitations = ref([]);

const profile = ref({ full_name: "", timezone: "" });
const savingProfile = ref(false);

const passwords = ref({ current_password: "", password: "", confirm: "" });
const savingPassword = ref(false);
const passwordError = ref("");

const canManage = computed(() => auth.canManageFamily);

// Sizes are charged against the quota by different things; showing them as one
// bar with no breakdown is how people end up unable to explain a full vault.
const breakdown = computed(() => {
  if (!storage.value) return [];

  const parts = [
    { key: "image", label: "Photos", color: "bg-primary-500", size: storage.value.by_type.image ?? 0, count: storage.value.counts.image ?? 0 },
    { key: "file", label: "Documents and files", color: "bg-secondary-600", size: storage.value.by_type.file ?? 0, count: storage.value.counts.file ?? 0 },
    { key: "versions", label: "Previous versions", color: "bg-warning-500", size: storage.value.versions.size, count: storage.value.versions.count },
    { key: "trashed", label: "In the bin", color: "bg-gray-400", size: storage.value.trashed.size, count: storage.value.trashed.count },
  ];

  // Whatever is left is real and charged, so name it rather than hiding it.
  const accounted = parts.reduce((sum, p) => sum + p.size, 0);
  const other = storage.value.used - accounted;
  if (other > 0) {
    parts.push({ key: "other", label: "Other", color: "bg-gray-300", size: other, count: null });
  }

  return parts.filter((p) => p.size > 0);
});

onMounted(load);

async function load() {
  loading.value = true;
  error.value = "";

  try {
    const [accountRes, sessionRes] = await Promise.all([
      api.get("/account"),
      api.get("/sessions"),
    ]);

    account.value = accountRes.data.account;
    storage.value = accountRes.data.storage;
    sessions.value = sessionRes.data.sessions;
    profile.value = {
      full_name: account.value.full_name ?? "",
      timezone: account.value.timezone ?? "",
    };

    if (auth.family) {
      const { data } = await api.get(`/families/${auth.family.id}`);
      members.value = data.members;
      invitations.value = data.invitations;
    }
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    loading.value = false;
  }
}

async function saveProfile() {
  savingProfile.value = true;
  error.value = "";

  try {
    const { data } = await api.patch("/account", profile.value);
    account.value = data.account;
    auth.updateUser({ full_name: data.account.full_name });
    toast.show({ message: "Profile saved" });
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    savingProfile.value = false;
  }
}

async function savePassword() {
  passwordError.value = "";

  if (passwords.value.password !== passwords.value.confirm) {
    passwordError.value = "The two new passwords do not match.";
    return;
  }

  savingPassword.value = true;
  try {
    const { data } = await api.patch("/account/password", {
      current_password: passwords.value.current_password,
      password: passwords.value.password,
    });

    passwords.value = { current_password: "", password: "", confirm: "" };
    sessions.value = await api.get("/sessions").then((r) => r.data.sessions);

    toast.show({
      message: "Password changed",
      detail: data.sessions_ended
        ? `${data.sessions_ended} other ${data.sessions_ended === 1 ? "device was" : "devices were"} signed out.`
        : "No other devices were signed in.",
    });
  } catch (e) {
    passwordError.value = e.userMessage;
  } finally {
    savingPassword.value = false;
  }
}

async function revokeSession(session) {
  const ok = await dialog.confirm({
    title: "Sign out this device?",
    message: `${session.device} will have to sign in again.`,
    detail: session.ip_address ? `Last seen at ${session.ip_address}.` : undefined,
    confirmLabel: "Sign it out",
    danger: true,
  });
  if (!ok) return;

  try {
    await api.delete(`/sessions/${session.id}`);
    sessions.value = sessions.value.filter((s) => s.id !== session.id);
    toast.show({ message: "Device signed out", detail: session.device });
  } catch (e) {
    error.value = e.userMessage;
  }
}

async function revokeOthers() {
  const others = sessions.value.filter((s) => !s.current).length;

  const ok = await dialog.confirm({
    title: "Sign out every other device?",
    message: `${others} ${others === 1 ? "device" : "devices"} will have to sign in again. This one stays signed in.`,
    confirmLabel: "Sign them out",
    danger: true,
  });
  if (!ok) return;

  try {
    await api.delete("/sessions");
    sessions.value = sessions.value.filter((s) => s.current);
    toast.show({ message: "Other devices signed out" });
  } catch (e) {
    error.value = e.userMessage;
  }
}

async function changeRole(member, role) {
  try {
    const { data } = await api.patch(`/families/${auth.family.id}/members/${member.id}`, { role });
    members.value = members.value.map((m) => (m.id === member.id ? data.member : m));
    toast.show({ message: `${data.member.user.full_name} is now ${role}` });
  } catch (e) {
    error.value = e.userMessage;
  }
}

async function removeMember(member) {
  const ok = await dialog.confirm({
    title: `Remove ${member.user.full_name}?`,
    message: "They lose access to everything the family has shared.",
    detail: "Files they uploaded stay in the vault.",
    confirmLabel: "Remove",
    danger: true,
  });
  if (!ok) return;

  try {
    await api.delete(`/families/${auth.family.id}/members/${member.id}`);
    members.value = members.value.filter((m) => m.id !== member.id);
    toast.show({ message: "Member removed", detail: member.user.full_name });
  } catch (e) {
    error.value = e.userMessage;
  }
}
</script>

<template>
  <section>
    <header class="mb-6">
      <h1 class="text-h2 font-bold text-gray-800">Settings</h1>
      <p class="mt-1 text-body-sm text-gray-500">Your account, your devices, and who else is in the vault</p>
    </header>

    <p v-if="error" role="alert" class="mb-4 rounded-base bg-error-50 px-4 py-3 text-body-sm text-error-600">
      {{ error }}
    </p>

    <div class="flex flex-col gap-6 lg:flex-row">
      <nav class="shrink-0 lg:w-52" aria-label="Settings sections">
        <ul class="flex gap-2 overflow-x-auto lg:flex-col lg:overflow-visible">
          <li v-for="option in SECTIONS" :key="option.value">
            <button
              type="button"
              :aria-current="section === option.value ? 'page' : undefined"
              :class="[
                'flex w-full items-center gap-3 whitespace-nowrap rounded-lg px-4 py-2 text-body font-medium transition',
                section === option.value
                  ? 'bg-primary-50 text-primary-700'
                  : 'text-gray-600 hover:bg-gray-100',
              ]"
              @click="section = option.value"
            >
              <i :class="['fas', option.icon, 'w-4']" aria-hidden="true"></i>
              {{ option.label }}
            </button>
          </li>
        </ul>
      </nav>

      <div class="min-w-0 flex-1">
        <div v-if="loading" class="space-y-3">
          <div v-for="n in 3" :key="n" class="h-24 animate-pulse rounded-lg bg-gray-100"></div>
        </div>

        <!-- Profile -->
        <div v-else-if="section === 'profile'" class="rounded-lg border border-gray-200 bg-white p-6">
          <h2 class="text-h3 font-semibold text-gray-800">Profile</h2>

          <form class="mt-5 max-w-md space-y-4" novalidate @submit.prevent="saveProfile">
            <div>
              <label for="full-name" class="mb-1 block text-body-sm font-medium text-gray-700">Name</label>
              <input
                id="full-name"
                v-model="profile.full_name"
                type="text"
                class="w-full rounded-base border border-gray-300 px-3 py-2 outline-none focus:ring-2 focus:ring-primary-500"
              />
            </div>

            <div>
              <label for="timezone" class="mb-1 block text-body-sm font-medium text-gray-700">Time zone</label>
              <input
                id="timezone"
                v-model="profile.timezone"
                type="text"
                placeholder="Europe/London"
                class="w-full rounded-base border border-gray-300 px-3 py-2 outline-none focus:ring-2 focus:ring-primary-500"
              />
              <p class="mt-1 text-caption text-gray-500">Used to decide what counts as "today" in your photo filters.</p>
            </div>

            <div>
              <span class="mb-1 block text-body-sm font-medium text-gray-700">Email</span>
              <p class="rounded-base bg-gray-50 px-3 py-2 text-body text-gray-600">{{ account.email }}</p>
              <p class="mt-1 text-caption text-gray-500">
                This is how you sign in. Changing it is not supported yet.
              </p>
            </div>

            <button
              type="submit"
              :disabled="savingProfile"
              class="rounded-base gradient-main px-5 py-2 text-body font-semibold text-white disabled:opacity-60"
            >
              {{ savingProfile ? "Saving…" : "Save changes" }}
            </button>
          </form>
        </div>

        <!-- Security -->
        <div v-else-if="section === 'security'" class="space-y-6">
          <div class="rounded-lg border border-gray-200 bg-white p-6">
            <h2 class="text-h3 font-semibold text-gray-800">Change password</h2>
            <p class="mt-1 text-body-sm text-gray-500">
              Every other signed-in device is signed out when you change it.
            </p>

            <p v-if="passwordError" role="alert" class="mt-4 rounded-base bg-error-50 px-3 py-2 text-body-sm text-error-600">
              {{ passwordError }}
            </p>

            <form class="mt-5 max-w-md space-y-4" novalidate @submit.prevent="savePassword">
              <div>
                <label for="current-password" class="mb-1 block text-body-sm font-medium text-gray-700">Current password</label>
                <input
                  id="current-password"
                  v-model="passwords.current_password"
                  type="password"
                  autocomplete="current-password"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 outline-none focus:ring-2 focus:ring-primary-500"
                />
              </div>
              <div>
                <label for="new-password" class="mb-1 block text-body-sm font-medium text-gray-700">New password</label>
                <input
                  id="new-password"
                  v-model="passwords.password"
                  type="password"
                  autocomplete="new-password"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 outline-none focus:ring-2 focus:ring-primary-500"
                />
                <p class="mt-1 text-caption text-gray-500">At least 8 characters.</p>
              </div>
              <div>
                <label for="confirm-password" class="mb-1 block text-body-sm font-medium text-gray-700">Confirm new password</label>
                <input
                  id="confirm-password"
                  v-model="passwords.confirm"
                  type="password"
                  autocomplete="new-password"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 outline-none focus:ring-2 focus:ring-primary-500"
                />
              </div>

              <button
                type="submit"
                :disabled="savingPassword || !passwords.current_password || !passwords.password"
                class="rounded-base gradient-main px-5 py-2 text-body font-semibold text-white disabled:opacity-60"
              >
                {{ savingPassword ? "Changing…" : "Change password" }}
              </button>
            </form>
          </div>

          <div class="rounded-lg border border-gray-200 bg-white p-6">
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h2 class="text-h3 font-semibold text-gray-800">Signed-in devices</h2>
                <p class="mt-1 text-body-sm text-gray-500">
                  Each of these can stay signed in without your password. Sign out anything you do not recognise.
                </p>
              </div>
              <button
                v-if="sessions.filter((s) => !s.current).length"
                type="button"
                class="shrink-0 rounded-base border border-error-500 px-3 py-2 text-body-sm font-semibold text-error-600 transition hover:bg-error-50"
                @click="revokeOthers"
              >
                Sign out all others
              </button>
            </div>

            <ul class="mt-5 space-y-2">
              <li
                v-for="session in sessions"
                :key="session.id"
                class="flex items-center gap-4 rounded-base border border-gray-200 p-4"
              >
                <i class="fas fa-desktop text-xl text-gray-400" aria-hidden="true"></i>

                <div class="min-w-0 flex-1">
                  <p class="text-body font-medium text-gray-800">
                    {{ session.device }}
                    <span v-if="session.current" class="ml-2 rounded-full bg-success-50 px-2 py-0.5 text-caption font-semibold text-success-700">
                      This device
                    </span>
                  </p>
                  <p class="text-caption text-gray-500">
                    {{ session.ip_address }} · signed in {{ formatRelativeDate(session.created_at) }}
                    <span v-if="session.last_used_at"> · last used {{ formatRelativeDate(session.last_used_at) }}</span>
                  </p>
                </div>

                <button
                  v-if="!session.current"
                  type="button"
                  class="shrink-0 rounded-md p-2 text-error-500 transition hover:bg-error-50"
                  :aria-label="`Sign out ${session.device}`"
                  @click="revokeSession(session)"
                >
                  <i class="fas fa-right-from-bracket" aria-hidden="true"></i>
                </button>
              </li>
            </ul>
          </div>
        </div>

        <!-- Family -->
        <div v-else-if="section === 'family'" class="rounded-lg border border-gray-200 bg-white p-6">
          <h2 class="text-h3 font-semibold text-gray-800">{{ auth.family?.name ?? "Family" }}</h2>
          <p class="mt-1 text-body-sm text-gray-500">
            <template v-if="canManage">Everyone who can reach what the family shares.</template>
            <template v-else>Only an admin can change roles or remove members.</template>
          </p>

          <ul class="mt-5 space-y-2">
            <li
              v-for="member in members"
              :key="member.id"
              class="flex flex-wrap items-center gap-4 rounded-base border border-gray-200 p-4"
            >
              <span
                class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary-50 text-body font-semibold text-primary-700"
                aria-hidden="true"
              >
                {{ (member.user.full_name || member.user.email).charAt(0).toUpperCase() }}
              </span>

              <div class="min-w-0 flex-1">
                <p class="truncate text-body font-medium text-gray-800">
                  {{ member.user.full_name }}
                  <span v-if="member.user.id === auth.user?.id" class="text-caption text-gray-400">(you)</span>
                </p>
                <p class="truncate text-caption text-gray-500">{{ member.user.email }}</p>
              </div>

              <span
                v-if="member.role === 'owner' || !canManage"
                class="rounded-full bg-gray-100 px-3 py-1 text-caption font-semibold capitalize text-gray-600"
              >
                {{ member.role }}
              </span>

              <template v-else>
                <label :for="`role-${member.id}`" class="sr-only">Role for {{ member.user.full_name }}</label>
                <select
                  :id="`role-${member.id}`"
                  :value="member.role"
                  class="rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
                  @change="changeRole(member, $event.target.value)"
                >
                  <option value="admin">Admin</option>
                  <option value="editor">Editor</option>
                  <option value="viewer">Viewer</option>
                </select>

                <button
                  type="button"
                  class="rounded-md p-2 text-error-500 transition hover:bg-error-50"
                  :aria-label="`Remove ${member.user.full_name}`"
                  @click="removeMember(member)"
                >
                  <i class="fas fa-user-minus" aria-hidden="true"></i>
                </button>
              </template>
            </li>
          </ul>

          <div v-if="invitations.length" class="mt-6">
            <h3 class="text-body font-semibold text-gray-700">Invited, not joined yet</h3>
            <ul class="mt-2 space-y-2">
              <li
                v-for="invitation in invitations"
                :key="invitation.id"
                class="flex items-center justify-between gap-4 rounded-base border border-dashed border-gray-300 p-3"
              >
                <span class="truncate text-body-sm text-gray-600">{{ invitation.email }}</span>
                <span class="shrink-0 text-caption capitalize text-gray-500">{{ invitation.role }}</span>
              </li>
            </ul>
          </div>
        </div>

        <!-- Storage -->
        <div v-else class="rounded-lg border border-gray-200 bg-white p-6">
          <h2 class="text-h3 font-semibold text-gray-800">Storage</h2>
          <p class="mt-1 text-body-sm text-gray-500">
            {{ formatFileSize(storage.used) }} of {{ formatFileSize(storage.quota) }} used
          </p>

          <div class="mt-5 flex h-3 overflow-hidden rounded-full bg-gray-100">
            <div
              v-for="part in breakdown"
              :key="part.key"
              :class="[part.color, 'h-full']"
              :style="{ width: `${(part.size / storage.quota) * 100}%` }"
              :title="`${part.label}: ${formatFileSize(part.size)}`"
            ></div>
          </div>

          <ul class="mt-5 space-y-3">
            <li v-for="part in breakdown" :key="part.key" class="flex items-center gap-3">
              <span :class="[part.color, 'h-3 w-3 shrink-0 rounded-sm']" aria-hidden="true"></span>
              <span class="flex-1 text-body text-gray-700">
                {{ part.label }}
                <span v-if="part.count !== null" class="text-caption text-gray-500">
                  · {{ part.count }} {{ part.count === 1 ? "item" : "items" }}
                </span>
              </span>
              <span class="text-body-sm font-medium text-gray-800">{{ formatFileSize(part.size) }}</span>
            </li>
          </ul>

          <p v-if="storage.versions.size > 0" class="mt-6 rounded-base bg-gray-50 px-4 py-3 text-body-sm text-gray-600">
            Previous versions are kept every time you replace a file — including the
            unsigned original of anything you have signed. Emptying the bin does not
            remove them.
          </p>
        </div>
      </div>
    </div>
  </section>
</template>
