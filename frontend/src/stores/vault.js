import { defineStore } from "pinia";
import { computed, ref } from "vue";
import api, { setVaultToken } from "@/api/client";

/**
 * The private section.
 *
 * The unlock token lives in the API client's memory, not here and not on disk,
 * so closing the tab locks the section. This store only remembers what the
 * screen needs to know about it.
 */
export const useVaultStore = defineStore("vault", () => {
  const exists = ref(false);
  const unlocked = ref(false);
  const recoveryAcknowledged = ref(false);
  const lockedFiles = ref(0);
  const lockedFolders = ref(0);
  const checked = ref(false);
  const busy = ref(false);

  // Shown once, never fetched again — the API cannot produce it a second time.
  const recoveryKey = ref("");

  const needsSetup = computed(() => checked.value && !exists.value);

  function apply(data) {
    exists.value = data.exists;
    unlocked.value = data.unlocked;
    recoveryAcknowledged.value = data.recovery_key_acknowledged;
    lockedFiles.value = data.locked_files ?? 0;
    lockedFolders.value = data.locked_folders ?? 0;
    checked.value = true;

    if (data.token) setVaultToken(data.token);
    if (data.recovery_key) recoveryKey.value = data.recovery_key;
  }

  async function refresh() {
    try {
      const { data } = await api.get("/vault");
      apply(data);
    } catch {
      // Not knowing is the same as locked, as far as the screen is concerned.
      checked.value = true;
    }
  }

  async function setUp(passphrase) {
    busy.value = true;
    try {
      const { data } = await api.post("/vault", { passphrase });
      apply(data);
    } finally {
      busy.value = false;
    }
  }

  async function unlock(passphrase) {
    busy.value = true;
    try {
      const { data } = await api.post("/vault/unlock", { passphrase });
      apply(data);
    } finally {
      busy.value = false;
    }
  }

  async function lock() {
    const { data } = await api.delete("/vault/unlock");
    setVaultToken(null);
    apply(data);
  }

  async function changePassphrase(current, next) {
    busy.value = true;
    try {
      const { data } = await api.patch("/vault/passphrase", {
        current_passphrase: current,
        passphrase: next,
      });
      apply(data);
    } finally {
      busy.value = false;
    }
  }

  async function recover(recovery, passphrase) {
    busy.value = true;
    try {
      const { data } = await api.post("/vault/recover", {
        recovery_key: recovery,
        passphrase,
      });
      apply(data);
    } finally {
      busy.value = false;
    }
  }

  /** Stops the app nagging about writing the recovery key down. */
  async function acknowledgeRecoveryKey() {
    recoveryKey.value = "";
    try {
      const { data } = await api.post("/vault/recovery_key_seen");
      apply(data);
    } catch {
      // Cosmetic; not worth surfacing.
    }
  }

  return {
    exists,
    unlocked,
    recoveryAcknowledged,
    recoveryKey,
    lockedFiles,
    lockedFolders,
    checked,
    busy,
    needsSetup,
    refresh,
    setUp,
    unlock,
    lock,
    changePassphrase,
    recover,
    acknowledgeRecoveryKey,
  };
});
