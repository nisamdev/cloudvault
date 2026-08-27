import { computed, ref } from "vue";
import api from "@/api/client";

/**
 * Destination picker for "Move to Private".
 *
 * Mounted once via <PrivateDestinationPicker />; callers await pick().
 * Files must land in a locked folder; folders may also sit at Private root.
 */
const open = ref(false);
const title = ref("Move to Private");
const allowRoot = ref(false);
const folders = ref([]);
const loading = ref(false);
const error = ref("");
let pending = null;

function settle(value) {
  const resolve = pending;
  pending = null;
  open.value = false;
  folders.value = [];
  error.value = "";
  resolve?.(value);
}

function folderPath(folder, byId) {
  const parts = [folder.name];
  let parentId = folder.parent_id;
  const seen = new Set([folder.id]);
  while (parentId && byId.has(parentId) && !seen.has(parentId)) {
    seen.add(parentId);
    const parent = byId.get(parentId);
    if (!parent) break;
    parts.unshift(parent.name);
    parentId = parent.parent_id;
  }
  return parts.join(" / ");
}

export function usePrivateDestination() {
  const destinations = computed(() => {
    const byId = new Map(folders.value.map((f) => [f.id, f]));
    return folders.value
      .map((folder) => ({ folder, path: folderPath(folder, byId) }))
      .sort((a, b) => a.path.localeCompare(b.path));
  });

  /**
   * @param {{ title?: string, allowRoot?: boolean }} [options]
   *   allowRoot — folders can sit at the top of Private (folderId null).
   * @returns {Promise<number|null|undefined>}
   *   number = locked folder id
   *   null   = Private root (only when allowRoot)
   *   undefined = cancelled
   */
  async function pick({ title: nextTitle = "Move to Private", allowRoot: root = false } = {}) {
    title.value = nextTitle;
    allowRoot.value = root;
    loading.value = true;
    error.value = "";
    open.value = true;

    try {
      const { data } = await api.get("/folders", { params: { locked: "true" } });
      folders.value = data.folders ?? [];
    } catch (e) {
      error.value = e.userMessage || "Could not load private folders.";
      folders.value = [];
    } finally {
      loading.value = false;
    }

    return new Promise((resolve) => {
      pending = resolve;
    });
  }

  function choose(folderId) {
    settle(folderId);
  }

  function chooseRoot() {
    if (!allowRoot.value) return;
    settle(null);
  }

  function cancel() {
    settle(undefined);
  }

  /** Creates a new top-level private folder and selects it. */
  async function createAndChoose(name) {
    const trimmed = name?.trim();
    if (!trimmed) return;

    loading.value = true;
    error.value = "";
    try {
      const { data } = await api.post("/folders", {
        folder: { name: trimmed, parent_id: null },
        locked: "true",
      });
      settle(data.folder.id);
    } catch (e) {
      error.value = e.userMessage || "Could not create that folder.";
      loading.value = false;
    }
  }

  return {
    open,
    title,
    allowRoot,
    folders,
    destinations,
    loading,
    error,
    pick,
    choose,
    chooseRoot,
    cancel,
    createAndChoose,
  };
}
