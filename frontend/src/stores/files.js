import { defineStore } from "pinia";
import { computed, ref } from "vue";
import api from "@/api/client";

export const useFilesStore = defineStore("files", () => {
  const items = ref([]);
  const loading = ref(false);
  const error = ref("");
  const page = ref(1);
  const totalPages = ref(1);
  const totalCount = ref(0);

  // Keyed by a client-side id so several concurrent uploads can each show their
  // own progress bar.
  const uploads = ref([]);

  const hasFiles = computed(() => items.value.length > 0);
  const isEmpty = computed(() => !loading.value && items.value.length === 0);

  async function fetchFiles({
    fileType = null,
    folderId = undefined,
    labelIds = [],
    trashed = false,
    q = "",
    page: pageNum = 1,
  } = {}) {
    loading.value = true;
    error.value = "";

    try {
      const { data, headers } = await api.get("/files", {
        params: {
          file_type: fileType || undefined,
          // Three distinct meanings, so `undefined` and `""` must survive:
          //   undefined -> every folder (used while searching)
          //   ""        -> the root level only
          //   <id>      -> that folder
          folder_id: folderId,
          label_ids: labelIds?.length ? labelIds : undefined,
          trashed: trashed ? "true" : undefined,
          q: q || undefined,
          page: pageNum,
        },
      });

      items.value = data.files;
      page.value = Number(headers["x-page"] ?? 1);
      totalPages.value = Number(headers["x-total-pages"] ?? 1);
      totalCount.value = Number(headers["x-total-count"] ?? data.files.length);
    } catch (e) {
      error.value = e.userMessage;
      throw e;
    } finally {
      loading.value = false;
    }
  }

  async function upload(file, { visibility = "private", folderId = null } = {}) {
    const tracker = {
      id: `${Date.now()}-${file.name}`,
      name: file.name,
      size: file.size,
      progress: 0,
      status: "uploading",
      error: "",
    };
    uploads.value.push(tracker);

    const formData = new FormData();
    formData.append("file", file);
    formData.append("visibility", visibility);
    if (folderId) formData.append("folder_id", folderId);

    try {
      const { data } = await api.post("/files", formData, {
        onUploadProgress: (event) => {
          if (!event.total) return;
          tracker.progress = Math.round((event.loaded * 100) / event.total);
        },
      });

      tracker.status = "done";
      tracker.progress = 100;

      // A re-upload returns the same id with a new version; replace in place
      // rather than showing the file twice.
      const existing = items.value.findIndex((f) => f.id === data.file.id);
      if (existing >= 0) {
        // A re-upload returns the same id with a new version number.
        items.value.splice(existing, 1, data.file);
      } else {
        items.value.unshift(data.file);
        // Keep the "N files" header honest without refetching the whole list.
        totalCount.value += 1;
      }

      return data.file;
    } catch (e) {
      tracker.status = "failed";
      tracker.error = e.userMessage;
      throw e;
    } finally {
      // Leave failures on screen so the user can read why.
      if (tracker.status === "done") {
        setTimeout(() => {
          uploads.value = uploads.value.filter((u) => u.id !== tracker.id);
        }, 2000);
      }
    }
  }

  async function trash(file) {
    await api.delete(`/files/${file.id}`);
    items.value = items.value.filter((f) => f.id !== file.id);
  }

  async function restore(file) {
    const { data } = await api.post(`/files/${file.id}/restore`);
    items.value = items.value.filter((f) => f.id !== file.id);
    return data.file;
  }

  /**
   * Downloads go through the API to get a short-lived presigned URL, then the
   * browser navigates to object storage directly. A plain link cannot be used:
   * the API needs the bearer token that only XHR can attach.
   */
  async function download(file) {
    const { data } = await api.get(`/files/${file.id}/download`);
    window.location.assign(data.url);
  }

  /** Renames a file in place. */
  async function rename(file, name) {
    const { data } = await api.patch(`/files/${file.id}`, { name });

    const index = items.value.findIndex((f) => f.id === file.id);
    if (index >= 0) items.value.splice(index, 1, data.file);

    return data.file;
  }

  /** Moves a file into a folder (null/"" = the root). */
  async function move(file, folderId) {
    const { data } = await api.patch(`/files/${file.id}`, { folder_id: folderId ?? "" });

    // The file has left the folder currently on screen, so drop it from the list.
    items.value = items.value.filter((f) => f.id !== file.id);
    totalCount.value = Math.max(totalCount.value - 1, 0);

    return data.file;
  }

  function dismissUpload(id) {
    uploads.value = uploads.value.filter((u) => u.id !== id);
  }

  return {
    items,
    uploads,
    loading,
    error,
    page,
    totalPages,
    totalCount,
    hasFiles,
    isEmpty,
    fetchFiles,
    upload,
    trash,
    restore,
    download,
    move,
    rename,
    dismissUpload,
  };
});
