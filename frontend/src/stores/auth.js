import { defineStore } from "pinia";
import { computed, ref } from "vue";
import api, { setAccessToken } from "@/api/client";

export const useAuthStore = defineStore("auth", () => {
  const user = ref(null);
  const family = ref(null);
  // An account may belong to several families, or to none.
  const families = ref([]);
  // Distinguishes "not signed in" from "haven't checked yet" — the router needs
  // that difference to avoid bouncing a valid session to /login on first load.
  const sessionChecked = ref(false);
  const loading = ref(false);

  const isAuthenticated = computed(() => user.value !== null);
  const needsFamilySetup = computed(
    () => isAuthenticated.value && family.value === null,
  );
  const role = computed(() => family.value?.role ?? null);

  // Permission helpers mirror PermissionChecker on the API. The server is still
  // the authority; these only decide what to show.
  const canEdit = computed(() => ["owner", "admin", "editor"].includes(role.value));
  const canShare = computed(() => ["owner", "admin", "editor"].includes(role.value));
  const canManageFamily = computed(() => ["owner", "admin"].includes(role.value));

  function applySession({
    access_token: token,
    user: sessionUser,
    family: sessionFamily,
    families: sessionFamilies,
  }) {
    setAccessToken(token ?? null);
    user.value = sessionUser ?? null;
    family.value = sessionFamily ?? null;
    families.value = sessionFamilies ?? [];
    sessionChecked.value = true;
  }

  async function switchFamily(id) {
    const { data } = await api.post(`/families/${id}/select`);
    family.value = { ...data.family };
    return data.family;
  }

  function clearSession() {
    setAccessToken(null);
    user.value = null;
    family.value = null;
    families.value = [];
    sessionChecked.value = true;
  }

  async function login(email, password, rememberMe = false) {
    loading.value = true;
    try {
      const { data } = await api.post("/auth/login", {
        email,
        password,
        remember_me: rememberMe,
      });
      applySession(data);
      return data;
    } finally {
      loading.value = false;
    }
  }

  async function register(payload) {
    loading.value = true;
    try {
      const { data } = await api.post("/auth/register", payload);
      applySession(data);
      return data;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Called once on app start. The access token only ever lives in memory, so
   * after a reload we exchange the httpOnly refresh cookie for a new one.
   * A 401 here is the normal "not signed in" path, not an error.
   */
  async function restoreSession() {
    if (sessionChecked.value) return;

    try {
      const { data } = await api.post("/auth/refresh", {}, { _skipAuthRetry: true });
      applySession(data);
    } catch {
      clearSession();
    }
  }

  // Settings can change the profile without re-fetching the whole session.
  function updateUser(patch) {
    if (user.value) user.value = { ...user.value, ...patch };
  }

  async function logout() {
    try {
      await api.post("/auth/logout");
    } catch {
      // Even if the server call fails, drop local state — the user asked to leave.
    } finally {
      clearSession();
    }
  }

  return {
    user,
    family,
    families,
    loading,
    sessionChecked,
    isAuthenticated,
    needsFamilySetup,
    role,
    canEdit,
    canShare,
    canManageFamily,
    login,
    register,
    restoreSession,
    switchFamily,
    updateUser,
    logout,
    clearSession,
  };
});
