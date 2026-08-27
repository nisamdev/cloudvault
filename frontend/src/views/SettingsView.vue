<script setup>
import { computed, onMounted, ref, watch } from "vue";
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
  { value: "reminders", label: "Reminders", icon: "fa-bell" },
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

/* ---------------------------------------------------------------- reminders */

const reminders = ref({ enabled: true, scope: "family", email: "", would_write_about: 0 });
const upcoming = ref([]);
const loadingUpcoming = ref(false);
const savingReminders = ref(false);

async function loadReminders() {
  loadingUpcoming.value = true;
  try {
    const { data } = await api.get("/records/upcoming");
    reminders.value = data.reminders;
    upcoming.value = data.upcoming;
  } catch {
    // The section still works without the preview.
  } finally {
    loadingUpcoming.value = false;
  }
}

async function saveReminders() {
  savingReminders.value = true;
  try {
    await api.patch("/account", {
      reminders_enabled: reminders.value.enabled,
      reminder_scope: reminders.value.scope,
    });
    await loadReminders();
    toast.show({ message: "Reminder settings saved" });
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    savingReminders.value = false;
  }
}

watch(section, (value) => {
  if (value === "reminders" && !upcoming.value.length) loadReminders();
});

function daysLabel(days) {
  if (days < 0) return `${Math.abs(days)} days ago`;
  if (days === 0) return "today";
  if (days < 45) return `${days} days`;
  const months = Math.round(days / 30.44);
  return months < 12 ? `${months} months` : `${Math.round(months / 12)} years`;
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

const creatingFamily = ref(false);
const newFamilyName = ref("");
const showCreateFamily = ref(false);

async function createFamily() {
  creatingFamily.value = true;
  error.value = "";

  try {
    const { data } = await api.post("/families", { name: newFamilyName.value.trim() });
    auth.families.push({ id: data.family.id, name: data.family.name, role: data.family.role });
    auth.family = data.family;
    newFamilyName.value = "";
    showCreateFamily.value = false;
    await load();
    toast.show({ message: "Family created", detail: data.family.name });
  } catch (e) {
    error.value = e.userMessage;
  } finally {
    creatingFamily.value = false;
  }
}

async function switchTo(id) {
  if (id === auth.family?.id) return;

  try {
    await auth.switchFamily(id);
    await load();
  } catch (e) {
    error.value = e.userMessage;
  }
}

async function leaveFamily(entry) {
  const ok = await dialog.confirm({
    title: `Leave ${entry.name}?`,
    message: "You lose access to everything it shares.",
    detail: "Files you uploaded into it stay there.",
    confirmLabel: "Leave",
    danger: true,
  });
  if (!ok) return;

  try {
    await api.delete(`/families/${entry.id}/leave`);
    auth.families = auth.families.filter((f) => f.id !== entry.id);
    auth.family = auth.families.length ? { ...auth.families[0] } : null;
    await load();
    toast.show({ message: "You left", detail: entry.name });
  } catch (e) {
    error.value = e.userMessage;
  }
}

const invite = ref({ email: "", role: "viewer" });
const inviting = ref(false);
const inviteError = ref("");
// Shown once, after creating it: the token is not recoverable afterwards.
const inviteLink = ref(null);
const linkCopied = ref(false);

async function sendInvite() {
  inviteError.value = "";
  inviting.value = true;

  try {
    const { data } = await api.post(`/families/${auth.family.id}/invitations`, {
      email: invite.value.email.trim(),
      role: invite.value.role,
    });

    invitations.value = [...invitations.value, data.invitation];
    inviteLink.value = { email: data.invitation.email, url: data.invitation.accept_url };
    invite.value = { email: "", role: "viewer" };
    linkCopied.value = false;
  } catch (e) {
    inviteError.value = e.userMessage;
  } finally {
    inviting.value = false;
  }
}

async function copyInviteLink() {
  try {
    await navigator.clipboard.writeText(inviteLink.value.url);
    linkCopied.value = true;
  } catch {
    inviteError.value = "Couldn't copy automatically — select the link and copy it.";
  }
}

async function revokeInvitation(invitation) {
  const ok = await dialog.confirm({
    title: "Cancel this invitation?",
    message: `The link sent to ${invitation.email} stops working.`,
    confirmLabel: "Cancel invitation",
    danger: true,
  });
  if (!ok) return;

  try {
    await api.delete(`/families/${auth.family.id}/invitations/${invitation.id}`);
    invitations.value = invitations.value.filter((i) => i.id !== invitation.id);
    if (inviteLink.value?.email === invitation.email) inviteLink.value = null;
    toast.show({ message: "Invitation cancelled", detail: invitation.email });
  } catch (e) {
    error.value = e.userMessage;
  }
}

/**
 * Whether the family's own things are open to this person.
 *
 * Separate from their role, which says what they may *do* with them. A
 * household answers this person by person — the teenager trusted with the wifi
 * password and not with the mortgage — and nobody's private section is
 * affected either way.
 */
async function setVaultAccess(member, canUse) {
  try {
    const { data } = await api.patch(`/families/${auth.family.id}/members/${member.id}`, {
      can_use_vault: canUse,
    });
    members.value = members.value.map((m) => (m.id === member.id ? data.member : m));

    const name = data.member.user.full_name || data.member.user.email;
    toast.show({
      message: canUse
        ? `${name} can reach the family's things`
        : `${name} no longer reaches the family's things`,
    });
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

/** What the family kept when somebody left, in words rather than a count. */
function keptLabel(kept) {
  if (!kept) return undefined;

  const parts = [
    [kept.files, "file", "files"],
    [kept.records, "record", "records"],
    [kept.folders, "folder", "folders"],
  ]
    .filter(([n]) => n > 0)
    .map(([n, one, many]) => `${n} ${n === 1 ? one : many}`);

  if (!parts.length) return "They had shared nothing with the family.";

  return `${parts.join(", ")} they shared are now yours.`;
}

async function removeMember(member) {
  const ok = await dialog.confirm({
    title: `Remove ${member.user.full_name}?`,
    message: "They lose access to everything the family shares, straight away.",
    detail:
      "Anything they shared with the family stays and becomes yours — the passports they " +
      "scanned do not leave with them. Their own private files stay theirs.",
    confirmLabel: "Remove",
    danger: true,
  });
  if (!ok) return;

  try {
    const { data } = await api.delete(`/families/${auth.family.id}/members/${member.id}`);
    members.value = members.value.filter((m) => m.id !== member.id);
    toast.show({ message: `${member.user.full_name} removed`, detail: keptLabel(data?.kept) });
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
        <div v-else-if="section === 'reminders'" class="space-y-6">
          <div class="rounded-lg border border-gray-200 bg-white p-6">
            <h2 class="text-h3 font-semibold text-gray-800">Reminders</h2>
            <p class="mt-1 text-body-sm text-gray-500">
              One email a day at most, listing whatever is running out. Nothing is sent when there
              is nothing to say.
            </p>

            <div class="mt-5 max-w-md space-y-4">
              <label class="flex items-start gap-3">
                <input
                  v-model="reminders.enabled"
                  type="checkbox"
                  class="mt-1 accent-primary-600"
                />
                <span>
                  <span class="block text-body-sm font-medium text-gray-700">Write to me</span>
                  <span class="block text-caption text-gray-500">
                    Sent to {{ reminders.email }}
                  </span>
                </span>
              </label>

              <fieldset :class="reminders.enabled ? '' : 'opacity-50'">
                <legend class="mb-2 text-body-sm font-medium text-gray-700">About</legend>
                <label class="flex items-start gap-3">
                  <input
                    v-model="reminders.scope"
                    type="radio"
                    value="family"
                    :disabled="!reminders.enabled"
                    class="mt-1 accent-primary-600"
                  />
                  <span>
                    <span class="block text-body-sm text-gray-700">Everything I can see</span>
                    <span class="block text-caption text-gray-500">
                      Mine, and whatever the family shares — the car insurance is nobody's in
                      particular until it lapses.
                    </span>
                  </span>
                </label>
                <label class="mt-3 flex items-start gap-3">
                  <input
                    v-model="reminders.scope"
                    type="radio"
                    value="own"
                    :disabled="!reminders.enabled"
                    class="mt-1 accent-primary-600"
                  />
                  <span>
                    <span class="block text-body-sm text-gray-700">Only my own records</span>
                    <span class="block text-caption text-gray-500">
                      Somebody else in the family will still hear about the shared ones.
                    </span>
                  </span>
                </label>
              </fieldset>

              <button
                type="button"
                :disabled="savingReminders"
                class="rounded-base gradient-main px-5 py-2 text-body font-semibold text-white disabled:opacity-60"
                @click="saveReminders"
              >
                {{ savingReminders ? "Saving…" : "Save changes" }}
              </button>
            </div>
          </div>

          <!-- The setting is abstract until you can see what it would send. -->
          <div class="rounded-lg border border-gray-200 bg-white p-6">
            <h2 class="text-h3 font-semibold text-gray-800">What's running out</h2>
            <p class="mt-1 text-body-sm text-gray-500">
              <template v-if="reminders.would_write_about">
                {{ reminders.would_write_about }} of these will be written about. The rest just
                count down here.
              </template>
              <template v-else>
                Everything here counts down on screen. None of it is due a letter yet.
              </template>
            </p>

            <div v-if="loadingUpcoming" class="mt-4 space-y-2">
              <div v-for="n in 3" :key="n" class="h-10 animate-pulse rounded-base bg-gray-100"></div>
            </div>

            <p v-else-if="!upcoming.length" class="mt-4 text-body-sm text-gray-500">
              Nothing in the next few months.
            </p>

            <ul v-else class="mt-4 divide-y divide-gray-100">
              <li
                v-for="item in upcoming"
                :key="`${item.record_id}-${item.field_key}`"
                class="flex items-center justify-between gap-3 py-2.5"
              >
                <span class="min-w-0">
                  <RouterLink
                    :to="{ name: 'record', params: { id: item.record_id } }"
                    class="block truncate text-body-sm font-medium text-gray-800 hover:text-primary-600"
                  >
                    {{ item.title }}
                  </RouterLink>
                  <span class="block text-caption text-gray-500">{{ item.label }}</span>
                </span>
                <span
                  :class="[
                    'shrink-0 text-body-sm font-medium',
                    item.days < 0
                      ? 'text-error-600'
                      : item.days <= 30
                        ? 'text-error-600'
                        : item.days <= 90
                          ? 'text-warning-600'
                          : 'text-gray-500',
                  ]"
                >
                  {{ daysLabel(item.days) }}
                </span>
              </li>
            </ul>
          </div>
        </div>

        <div v-else-if="section === 'family'" class="space-y-6">
          <!-- An account can belong to several: "Family", "Parents' house",
               "Tax stuff with the accountant". Or to none, which is fine. -->
          <div class="rounded-lg border border-gray-200 bg-white p-6">
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h2 class="text-h3 font-semibold text-gray-800">Your families</h2>
                <p class="mt-1 text-body-sm text-gray-500">
                  A family is a group you share things with. You can be in as many as you like.
                </p>
              </div>
              <button
                type="button"
                class="shrink-0 rounded-base border border-gray-300 px-3 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
                @click="showCreateFamily = !showCreateFamily"
              >
                <i class="fas fa-plus mr-1" aria-hidden="true"></i>New family
              </button>
            </div>

            <form
              v-if="showCreateFamily"
              class="mt-4 flex flex-wrap items-end gap-3"
              novalidate
              @submit.prevent="createFamily"
            >
              <div class="min-w-56 flex-1">
                <label for="family-name" class="mb-1 block text-body-sm font-medium text-gray-700">Name</label>
                <input
                  id="family-name"
                  v-model="newFamilyName"
                  type="text"
                  placeholder="The Smith Family"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 outline-none focus:ring-2 focus:ring-primary-500"
                />
              </div>
              <button
                type="submit"
                :disabled="creatingFamily || !newFamilyName.trim()"
                class="rounded-base gradient-main px-5 py-2 text-body font-semibold text-white disabled:opacity-60"
              >
                {{ creatingFamily ? "Creating…" : "Create" }}
              </button>
            </form>

            <p v-if="!auth.families.length" class="mt-5 rounded-base bg-gray-50 px-4 py-6 text-center text-body text-gray-500">
              You're not in a family yet. Everything here is private to you — make one when
              you want to share.
            </p>

            <ul v-else class="mt-5 space-y-2">
              <li
                v-for="entry in auth.families"
                :key="entry.id"
                :class="[
                  'flex flex-wrap items-center gap-4 rounded-base border p-4',
                  entry.id === auth.family?.id ? 'border-primary-300 bg-primary-50' : 'border-gray-200',
                ]"
              >
                <i class="fas fa-users text-xl text-gray-400" aria-hidden="true"></i>

                <div class="min-w-0 flex-1">
                  <p class="truncate text-body font-medium text-gray-800">
                    {{ entry.name }}
                    <span v-if="entry.id === auth.family?.id" class="ml-2 text-caption text-primary-700">
                      Showing now
                    </span>
                  </p>
                  <p class="text-caption text-gray-500">
                    <span class="capitalize">{{ entry.role }}</span>
                    <!-- Still a member, still in the list, and nothing in it
                         reachable. Saying which beats a family that appears to
                         be empty. -->
                    <span v-if="entry.can_use_vault === false" class="ml-1 text-warning-600">
                      · no access to what it shares
                    </span>
                  </p>
                </div>

                <button
                  v-if="entry.id !== auth.family?.id"
                  type="button"
                  class="shrink-0 rounded-base border border-gray-300 px-3 py-1.5 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
                  @click="switchTo(entry.id)"
                >
                  Switch to
                </button>

                <button
                  v-if="entry.role !== 'owner'"
                  type="button"
                  class="shrink-0 rounded-md p-2 text-error-500 transition hover:bg-error-50"
                  :aria-label="`Leave ${entry.name}`"
                  @click="leaveFamily(entry)"
                >
                  <i class="fas fa-right-from-bracket" aria-hidden="true"></i>
                </button>
              </li>
            </ul>
          </div>

        <div v-if="auth.family" class="rounded-lg border border-gray-200 bg-white p-6">
          <h2 class="text-h3 font-semibold text-gray-800">{{ auth.family?.name ?? "Family" }}</h2>
          <p class="mt-1 text-body-sm text-gray-500">
            <template v-if="canManage">Everyone who can reach what the family shares.</template>
            <template v-else>Only an admin can change roles or remove members.</template>
          </p>

          <p v-if="canManage" class="mt-4 rounded-base bg-gray-50 px-4 py-3 text-caption text-gray-600">
            <strong class="font-medium text-gray-700">Family access</strong> is whether somebody
            reaches the family's shared records and files at all — their role decides what they may
            do once they are in. Everybody's own private section is theirs regardless: nobody sees
            inside it without the passphrase, not even you.
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

              <!-- Shut out of the family's things, but still in the family:
                   worth saying on the row rather than only in the switch. -->
              <span
                v-if="!member.can_use_vault"
                class="rounded-full bg-warning-50 px-3 py-1 text-caption font-medium text-warning-600"
                :title="member.vault_note || 'No access to the family\'s records and files'"
              >
                <i class="fas fa-lock mr-1" aria-hidden="true"></i>No family access
              </span>

              <span
                v-if="member.role === 'owner' || !canManage"
                class="rounded-full bg-gray-100 px-3 py-1 text-caption font-semibold capitalize text-gray-600"
              >
                {{ member.role }}
              </span>

              <template v-else>
                <label :for="`role-${member.id}`" class="sr-only">
                  What {{ member.user.full_name }} may do
                </label>
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

                <label
                  class="flex cursor-pointer items-center gap-2 text-body-sm text-gray-700"
                  :title="
                    member.can_use_vault
                      ? 'Turn off to shut them out of the family\'s records and files'
                      : 'Turn on to open the family\'s records and files to them'
                  "
                >
                  <input
                    type="checkbox"
                    class="rounded accent-primary-600"
                    :checked="member.can_use_vault"
                    @change="setVaultAccess(member, $event.target.checked)"
                  />
                  Family access
                </label>

                <!-- Was a bare icon, sitting after a dropdown and a tick box,
                     and read as decoration. Taking somebody out of the family
                     is the strongest thing on this row and has to be findable
                     by the word for it. -->
                <button
                  type="button"
                  class="shrink-0 rounded-base border border-gray-300 px-3 py-2 text-body-sm font-medium text-gray-700 transition hover:border-error-100 hover:bg-error-50 hover:text-error-600"
                  @click="removeMember(member)"
                >
                  <i class="fas fa-user-minus mr-1.5 text-error-500" aria-hidden="true"></i>
                  Remove
                </button>
              </template>
            </li>
          </ul>

          <div v-if="canManage" class="mt-8 border-t border-gray-200 pt-6">
            <h3 class="text-body font-semibold text-gray-700">Invite someone</h3>
            <p class="mt-1 text-body-sm text-gray-500">
              They get a link that lets them create an account and join this family.
            </p>

            <p v-if="inviteError" role="alert" class="mt-3 rounded-base bg-error-50 px-3 py-2 text-body-sm text-error-600">
              {{ inviteError }}
            </p>

            <form class="mt-4 flex flex-wrap items-end gap-3" novalidate @submit.prevent="sendInvite">
              <div class="min-w-56 flex-1">
                <label for="invite-email" class="mb-1 block text-body-sm font-medium text-gray-700">Email</label>
                <input
                  id="invite-email"
                  v-model="invite.email"
                  type="email"
                  required
                  placeholder="them@example.com"
                  class="w-full rounded-base border border-gray-300 px-3 py-2 outline-none focus:ring-2 focus:ring-primary-500"
                />
              </div>

              <div>
                <label for="invite-role" class="mb-1 block text-body-sm font-medium text-gray-700">Role</label>
                <select
                  id="invite-role"
                  v-model="invite.role"
                  class="rounded-base border border-gray-300 px-3 py-2 outline-none focus:ring-2 focus:ring-primary-500"
                >
                  <option value="admin">Admin — can invite and manage members</option>
                  <option value="editor">Editor — can upload and edit</option>
                  <option value="viewer">Viewer — can only look</option>
                </select>
              </div>

              <button
                type="submit"
                :disabled="inviting || !invite.email.trim()"
                class="rounded-base gradient-main px-5 py-2 text-body font-semibold text-white disabled:opacity-60"
              >
                {{ inviting ? "Inviting…" : "Send invite" }}
              </button>
            </form>

            <!-- Shown once. The link is emailed too, but a home server may have
                 no working SMTP, and a family is easier to reach on WhatsApp. -->
            <div v-if="inviteLink" class="mt-4 rounded-base border border-primary-200 bg-primary-50 p-4">
              <p class="text-body-sm font-medium text-primary-800">
                Invitation for {{ inviteLink.email }}
              </p>
              <p class="mt-1 text-caption text-primary-700">
                We emailed this link. You can also send it yourself — it is shown only now.
              </p>

              <div class="mt-3 flex flex-wrap gap-2">
                <label for="invite-link" class="sr-only">Invitation link</label>
                <input
                  id="invite-link"
                  :value="inviteLink.url"
                  readonly
                  class="min-w-56 flex-1 rounded-base border border-primary-200 bg-white px-3 py-2 font-mono text-caption text-gray-700"
                  @focus="$event.target.select()"
                />
                <button
                  type="button"
                  class="shrink-0 rounded-base bg-primary-600 px-4 py-2 text-body-sm font-semibold text-white transition hover:bg-primary-700"
                  @click="copyInviteLink"
                >
                  {{ linkCopied ? "Copied" : "Copy link" }}
                </button>
              </div>
            </div>
          </div>

          <div v-if="invitations.length" class="mt-6">
            <h3 class="text-body font-semibold text-gray-700">Invited, not joined yet</h3>
            <ul class="mt-2 space-y-2">
              <li
                v-for="invitation in invitations"
                :key="invitation.id"
                class="flex items-center justify-between gap-4 rounded-base border border-dashed border-gray-300 p-3"
              >
                <span class="min-w-0 flex-1 truncate text-body-sm text-gray-600">{{ invitation.email }}</span>
                <span class="shrink-0 text-caption capitalize text-gray-500">{{ invitation.role }}</span>
                <button
                  v-if="canManage"
                  type="button"
                  class="shrink-0 rounded-md p-2 text-error-500 transition hover:bg-error-50"
                  :aria-label="`Cancel invitation for ${invitation.email}`"
                  @click="revokeInvitation(invitation)"
                >
                  <i class="fas fa-xmark" aria-hidden="true"></i>
                </button>
              </li>
            </ul>
          </div>
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
