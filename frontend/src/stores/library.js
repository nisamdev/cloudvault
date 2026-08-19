import { defineStore } from "pinia";
import { computed, ref } from "vue";
import api from "@/api/client";

/**
 * Folders and labels — the organisational layer around files.
 *
 * Kept separate from the files store: the tree and the label list change rarely
 * and are shared by several screens, while the file list is refetched constantly.
 */
export const useLibraryStore = defineStore("library", () => {
  const folders = ref([]);
  const tree = ref([]);
  const labels = ref([]);
  const loading = ref(false);
  const error = ref("");

  // null = "All files" (search everywhere); "" = the root level.
  const currentFolderId = ref(null);
  const breadcrumbs = ref([]);
  const selectedLabelIds = ref([]);

  const currentFolder = computed(
    () => folders.value.find((f) => f.id === currentFolderId.value) ?? null,
  );

  const labelsById = computed(() =>
    Object.fromEntries(labels.value.map((label) => [label.id, label])),
  );

  async function fetchFolders() {
    loading.value = true;
    try {
      const { data } = await api.get("/folders");
      folders.value = data.folders;
      tree.value = data.tree;
    } catch (e) {
      error.value = e.userMessage;
    } finally {
      loading.value = false;
    }
  }

  async function fetchLabels() {
    try {
      const { data } = await api.get("/labels");
      labels.value = data.labels;
    } catch (e) {
      error.value = e.userMessage;
    }
  }

  async function createFolder({ name, parentId = null, shared = false }) {
    const { data } = await api.post("/folders", {
      folder: { name, parent_id: parentId },
      shared: shared ? "true" : undefined,
    });
    await fetchFolders();
    return data.folder;
  }

  async function renameFolder(folder, name) {
    await api.patch(`/folders/${folder.id}`, { folder: { name } });
    await fetchFolders();
  }

  async function moveFolder(folder, parentId) {
    await api.patch(`/folders/${folder.id}`, { folder: { parent_id: parentId } });
    await fetchFolders();
  }

  async function deleteFolder(folder) {
    await api.delete(`/folders/${folder.id}`);
    // Deleting the folder you are standing in would leave the view orphaned.
    if (currentFolderId.value === folder.id) currentFolderId.value = null;
    await fetchFolders();
  }

  // Folders directly inside the given parent (null = root). Drives the Drive-
  // style listing, where folders appear above files.
  function childFolders(parentId) {
    const target = parentId === null || parentId === undefined || parentId === "" ? null : parentId;
    return folders.value
      .filter((folder) => (folder.parent_id ?? null) === target)
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  // Every folder below the given one — used to stop a folder being dropped
  // into its own subtree.
  function descendantIds(folderId) {
    const out = [];
    let queue = folders.value.filter((f) => f.parent_id === folderId).map((f) => f.id);

    while (queue.length) {
      out.push(...queue);
      queue = folders.value.filter((f) => queue.includes(f.parent_id)).map((f) => f.id);
    }

    return out;
  }

  /**
   * Downloads a whole folder as a ZIP.
   *
   * Two steps: ask the API for a short-lived signed URL, then let the browser
   * navigate to it. A plain link cannot carry the bearer token, and streaming
   * the archive through JS would hold the whole thing in memory.
   */
  async function downloadFolder(folder) {
    const { data } = await api.post(`/folders/${folder.id}/download_url`);
    window.location.assign(data.url);
    return data;
  }

  async function openFolder(folderId) {
    currentFolderId.value = folderId;

    if (folderId === null || folderId === "") {
      breadcrumbs.value = [];
      return;
    }

    const { data } = await api.get(`/folders/${folderId}`);
    breadcrumbs.value = [...data.breadcrumbs, { id: data.folder.id, name: data.folder.name }];
  }

  async function createLabel({ name, color }) {
    const { data } = await api.post("/labels", { label: { name, color } });
    await fetchLabels();
    return data.label;
  }

  async function renameLabel(label, name) {
    await api.patch(`/labels/${label.id}`, { label: { name } });
    await fetchLabels();
  }

  async function deleteLabel(label) {
    await api.delete(`/labels/${label.id}`);
    selectedLabelIds.value = selectedLabelIds.value.filter((id) => id !== label.id);
    await fetchLabels();
  }

  function toggleLabelFilter(labelId) {
    const index = selectedLabelIds.value.indexOf(labelId);
    if (index >= 0) selectedLabelIds.value.splice(index, 1);
    else selectedLabelIds.value.push(labelId);
  }

  function clearLabelFilter() {
    selectedLabelIds.value = [];
  }

  return {
    folders,
    tree,
    labels,
    labelsById,
    loading,
    error,
    currentFolderId,
    currentFolder,
    breadcrumbs,
    selectedLabelIds,
    fetchFolders,
    fetchLabels,
    childFolders,
    descendantIds,
    createFolder,
    renameFolder,
    moveFolder,
    deleteFolder,
    openFolder,
    downloadFolder,
    createLabel,
    renameLabel,
    deleteLabel,
    toggleLabelFilter,
    clearLabelFilter,
  };
});
