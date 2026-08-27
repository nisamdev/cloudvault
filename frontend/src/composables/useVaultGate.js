import { ref } from "vue";
import { useVaultStore } from "@/stores/vault";

/**
 * The unlock / setup dialog for the private section.
 *
 * Module-level state and a single <VaultGate /> (in AppLayout), so any screen
 * can ask for the passphrase — including a context menu that wants to move
 * something in before the private section has been opened this session.
 */
const mode = ref("");
let pending = null;

function settle(value) {
  const resolve = pending;
  pending = null;
  mode.value = "";
  resolve?.(value);
}

export function useVaultGate() {
  const vault = useVaultStore();

  function open(next) {
    mode.value = next;
  }

  /** Cancel: closes the dialog and rejects any waiting ensureUnlocked(). */
  function close() {
    settle(false);
  }

  /** Success: closes the dialog and resolves any waiting ensureUnlocked(). */
  function complete() {
    settle(true);
  }

  /**
   * Opens setup or unlock when needed.
   * @returns {Promise<boolean>} true once the section is open, false if cancelled
   */
  async function ensureUnlocked() {
    if (!vault.checked) await vault.refresh();

    if (!vault.exists) {
      if (!mode.value) open("setup");
      return waitForUnlock();
    }

    if (vault.unlocked) return true;

    if (!mode.value) open("unlock");

    return waitForUnlock();
  }

  function waitForUnlock() {
    return new Promise((resolve) => {
      if (pending) {
        const prior = pending;
        pending = (value) => {
          prior(value);
          resolve(value && vault.unlocked);
        };
      } else {
        pending = (value) => resolve(value && vault.unlocked);
      }
    });
  }

  return { mode, open, close, complete, ensureUnlocked };
}
