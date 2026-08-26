<script setup>
import { computed, ref, watch } from "vue";
import { useVaultStore } from "@/stores/vault";
import { useVaultGate } from "@/composables/useVaultGate";
import { copyText } from "@/utils/clipboard";

/**
 * Everything that stands between someone and their private section: setting one
 * up, unlocking it, and the one showing of the recovery key.
 *
 * That last screen is deliberately hard to hurry past. The key is shown once
 * and cannot be produced again, and this is the moment somebody either writes
 * it down or loses the ability to ever get back in.
 *
 * Mounted once in AppLayout; other screens open it through useVaultGate().
 */
const vault = useVaultStore();
const gate = useVaultGate();

const passphrase = ref("");
const confirmation = ref("");
const currentPassphrase = ref("");
const recoveryInput = ref("");
const error = ref("");
const copied = ref(false);
const understood = ref(false);

const mode = gate.mode;
const showing = computed(() => vault.recoveryKey || mode.value);

const canSubmit = computed(() => {
  if (mode.value === "setup") {
    return passphrase.value.length >= 8 && passphrase.value === confirmation.value;
  }
  if (mode.value === "unlock") return passphrase.value.length > 0;
  if (mode.value === "change") {
    return (
      currentPassphrase.value.length > 0 &&
      passphrase.value.length >= 8 &&
      passphrase.value === confirmation.value
    );
  }
  if (mode.value === "recover") {
    return (
      recoveryInput.value.length > 0 &&
      passphrase.value.length >= 8 &&
      passphrase.value === confirmation.value
    );
  }
  return false;
});

watch(mode, () => {
  error.value = "";
  passphrase.value = "";
  confirmation.value = "";
  currentPassphrase.value = "";
  recoveryInput.value = "";
});

function open(next) {
  gate.open(next);
}

function close() {
  gate.close();
}

async function submit() {
  if (!canSubmit.value || vault.busy) return;
  error.value = "";

  try {
    if (mode.value === "setup") await vault.setUp(passphrase.value);
    else if (mode.value === "unlock") await vault.unlock(passphrase.value);
    else if (mode.value === "change") {
      await vault.changePassphrase(currentPassphrase.value, passphrase.value);
    } else if (mode.value === "recover") {
      await vault.recover(recoveryInput.value, passphrase.value);
    }

    gate.complete();
  } catch (e) {
    error.value = e.userMessage;
  }
}

async function copyRecoveryKey() {
  copied.value = await copyText(vault.recoveryKey);
}

function finishWithRecoveryKey() {
  understood.value = false;
  copied.value = false;
  vault.acknowledgeRecoveryKey();
}

defineExpose({ open });
</script>

<template>
  <div
    v-if="showing"
    class="fixed inset-0 z-50 flex items-center justify-center bg-gray-900/60 p-4"
    @click.self="vault.recoveryKey ? null : close()"
  >
    <!-- The recovery key, shown once and never again -->
    <div
      v-if="vault.recoveryKey"
      class="w-full max-w-lg rounded-xl bg-white p-6 shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-labelledby="recovery-title"
    >
      <h2 id="recovery-title" class="text-h3 font-semibold text-gray-800">
        <i class="fas fa-key mr-2 text-warning-600" aria-hidden="true"></i>
        Write this down now
      </h2>
      <p class="mt-2 text-body-sm text-gray-600">
        This is your recovery key. It is the only way back into your private section if you forget
        the passphrase — and it is shown once. We cannot produce it again, because we never keep it.
      </p>

      <p
        class="mt-4 select-all break-all rounded-base border-2 border-dashed border-gray-300 bg-gray-50 p-4 text-center font-mono text-h4 tracking-wider text-gray-800"
      >
        {{ vault.recoveryKey }}
      </p>

      <button
        type="button"
        class="mt-3 w-full rounded-base border border-gray-300 py-2 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
        @click="copyRecoveryKey"
      >
        <i :class="['fas mr-2', copied ? 'fa-check text-success-600' : 'fa-copy']" aria-hidden="true"></i>
        {{ copied ? "Copied — now put it somewhere that isn't CloudVault" : "Copy it" }}
      </button>

      <div class="mt-4 rounded-base bg-error-50 p-3 text-body-sm text-error-600">
        Keep it somewhere other than this vault. If you lose both the passphrase and this key, the
        files in your private section cannot be recovered by anyone, including us.
      </div>

      <label class="mt-4 flex items-start gap-2 text-body-sm text-gray-700">
        <input v-model="understood" type="checkbox" class="mt-1 accent-primary-600" />
        <span>I have written it down somewhere safe.</span>
      </label>

      <button
        type="button"
        :disabled="!understood"
        class="mt-4 w-full rounded-base gradient-main py-2.5 font-semibold text-white disabled:opacity-50"
        @click="finishWithRecoveryKey"
      >
        Done
      </button>
    </div>

    <!-- Setting up, unlocking, changing, recovering -->
    <div
      v-else
      class="w-full max-w-md rounded-xl bg-white p-6 shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-labelledby="vault-title"
    >
      <h2 id="vault-title" class="text-h3 font-semibold text-gray-800">
        <template v-if="mode === 'setup'">Set up your private section</template>
        <template v-else-if="mode === 'unlock'">Unlock your private section</template>
        <template v-else-if="mode === 'change'">Change your passphrase</template>
        <template v-else>Use your recovery key</template>
      </h2>

      <p v-if="mode === 'setup'" class="mt-2 text-body-sm text-gray-600">
        Files you put in here are encrypted with a key only your passphrase opens. Not even the
        database or the disk can read them without it.
      </p>
      <p v-else-if="mode === 'recover'" class="mt-2 text-body-sm text-gray-600">
        Type the recovery key you wrote down. You will then set a new passphrase, and get a new
        recovery key.
      </p>

      <p v-if="error" role="alert" class="mt-3 rounded-base bg-error-50 px-3 py-2 text-body-sm text-error-600">
        {{ error }}
      </p>

      <form class="mt-4 space-y-3" @submit.prevent="submit">
        <div v-if="mode === 'recover'">
          <label for="vault-recovery" class="mb-1 block text-body-sm font-medium text-gray-700">
            Recovery key
          </label>
          <input
            id="vault-recovery"
            v-model="recoveryInput"
            type="text"
            autocomplete="off"
            spellcheck="false"
            placeholder="XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX"
            class="w-full rounded-base border border-gray-300 px-3 py-2 font-mono text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          />
        </div>

        <div v-if="mode === 'change'">
          <label for="vault-current" class="mb-1 block text-body-sm font-medium text-gray-700">
            Current passphrase
          </label>
          <input
            id="vault-current"
            v-model="currentPassphrase"
            type="password"
            autocomplete="current-password"
            class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          />
        </div>

        <div>
          <label for="vault-passphrase" class="mb-1 block text-body-sm font-medium text-gray-700">
            {{ mode === "unlock" ? "Passphrase" : "New passphrase" }}
          </label>
          <input
            id="vault-passphrase"
            v-model="passphrase"
            type="password"
            :autocomplete="mode === 'unlock' ? 'current-password' : 'new-password'"
            class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          />
          <p v-if="mode !== 'unlock'" class="mt-1 text-caption text-gray-500">
            At least 8 characters. A few words you will remember beats something clever.
          </p>
        </div>

        <div v-if="mode !== 'unlock'">
          <label for="vault-confirm" class="mb-1 block text-body-sm font-medium text-gray-700">
            Type it again
          </label>
          <input
            id="vault-confirm"
            v-model="confirmation"
            type="password"
            autocomplete="new-password"
            class="w-full rounded-base border border-gray-300 px-3 py-2 text-body-sm outline-none focus:ring-2 focus:ring-primary-500"
          />
          <p v-if="confirmation && confirmation !== passphrase" class="mt-1 text-caption text-error-600">
            Those don't match.
          </p>
        </div>

        <div class="flex items-center gap-2 pt-1">
          <button
            type="submit"
            :disabled="!canSubmit || vault.busy"
            class="flex-1 rounded-base gradient-main py-2.5 font-semibold text-white disabled:opacity-50"
          >
            <span v-if="vault.busy">
              <i class="fas fa-circle-notch fa-spin mr-2" aria-hidden="true"></i>Working…
            </span>
            <span v-else-if="mode === 'setup'">Create it</span>
            <span v-else-if="mode === 'unlock'">Unlock</span>
            <span v-else-if="mode === 'change'">Change it</span>
            <span v-else>Set a new passphrase</span>
          </button>
          <button
            type="button"
            class="rounded-base border border-gray-300 px-4 py-2.5 text-body-sm font-medium text-gray-700 transition hover:bg-gray-50"
            @click="close"
          >
            Cancel
          </button>
        </div>
      </form>

      <button
        v-if="mode === 'unlock'"
        type="button"
        class="mt-3 text-body-sm text-gray-500 transition hover:text-primary-600"
        @click="open('recover')"
      >
        I've forgotten the passphrase
      </button>
    </div>
  </div>
</template>
