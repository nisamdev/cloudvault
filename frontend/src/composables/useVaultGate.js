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
   * Opens the unlock dialog when needed.
   * @returns {Promise<boolean>} true once the section is open, false if cancelled
   *   or if there is no private section yet.
   */
  async function ensureUnlocked() {
    if (!vault.checked) await vault.refresh();
    if (!vault.exists) return false;
    if (vault.unlocked) return true;

    if (!mode.value) open("unlock");

    return new Promise((resolve) => {
      if (pending) {
        const prior = pending;
        pending = (value) => {
          prior(value);
          resolve(value);
        };
      } else {
        pending = resolve;
      }
    });
  }

  return { mode, open, close, complete, ensureUnlocked };
}
