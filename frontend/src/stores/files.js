import { defineStore } from "pinia";
import { computed, ref } from "vue";
import api from "@/api/client";

export const useFilesStore = defineStore("files", () => {
  const items = ref([]);
  const loading = ref(false);
  const loadingMore = ref(false);
  const error = ref("");
  const page = ref(1);
  const totalPages = ref(1);
  const totalCount = ref(0);

  // Keyed by a client-side id so several concurrent uploads can each show their
  // own progress bar.
  const uploads = ref([]);

  const hasFiles = computed(() => items.value.length > 0);
  const isEmpty = computed(() => !loading.value && items.value.length === 0);
  const hasMore = computed(() => page.value < totalPages.value);

  // Remembered so loadMore() can ask for the next page of the same query.
  let lastQuery = {};

  async function fetchFiles({
    fileType = null,
    folderId = undefined,
    labelIds = [],
    trashed = false,
    q = "",
    page: pageNum = 1,
    append = false,
    // Gallery filters: owner_id, visibility, orientation, date_from, date_to,
    // sort. Passed through as-is so adding one needs no store change.
    filters = {},
  } = {}) {
    lastQuery = { fileType, folderId, labelIds, trashed, q, filters };
    loading.value = !append;
    loadingMore.value = append;
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
          ...Object.fromEntries(
            Object.entries(filters).filter(([, value]) => value !== "" && value != null),
          ),
        },
      });

      // Infinite scroll appends; every other call replaces.
      items.value = append ? [...items.value, ...data.files] : data.files;
      page.value = Number(headers["x-page"] ?? 1);
      totalPages.value = Number(headers["x-total-pages"] ?? 1);
      totalCount.value = Number(headers["x-total-count"] ?? data.files.length);
    } catch (e) {
      error.value = e.userMessage;
      throw e;
    } finally {
      loading.value = false;
      loadingMore.value = false;
    }
  }

  /** Fetches the next page of the current query and appends it. */
  async function loadMore() {
    if (loadingMore.value || loading.value || !hasMore.value) return;

    await fetchFiles({ ...lastQuery, page: page.value + 1, append: true });
  }

  /**
   * @param {File} file
   * @param {{ visibility?: string, folderId?: string|number|null, onProgress?: (pct: number, event: ProgressEvent) => void, track?: boolean }} [options]
   *   track — when false, skip the per-file progress row (batch UI owns progress).
   */
  async function upload(file, { visibility = "private", folderId = null, onProgress = null, track = true } = {}) {
    const tracker = {
      id: `${Date.now()}-${file.name}`,
      name: file.name,
      size: file.size,
      progress: 0,
      status: "uploading",
      error: "",
    };
    if (track) uploads.value.push(tracker);

    const formData = new FormData();
    formData.append("file", file);
    formData.append("visibility", visibility);
    if (folderId) formData.append("folder_id", folderId);
    // Windows "Date modified" — what the OS shows in Properties. Browsers expose
    // it as File.lastModified; WhatsApp photos often have no EXIF otherwise.
    if (file.lastModified) formData.append("last_modified", String(file.lastModified));

    try {
      const { data } = await api.post("/files", formData, {
        onUploadProgress: (event) => {
          if (!event.total) return;
          const pct = Math.round((event.loaded * 100) / event.total);
          tracker.progress = pct;
          onProgress?.(pct, event);
        },
      });

      tracker.status = "done";
      tracker.progress = 100;
      onProgress?.(100, { loaded: file.size, total: file.size });

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
      if (track) {
        // Leave failures on screen so the user can read why.
      } else {
        // Batch UI surfaces failures; keep a dismissible row for detail.
        uploads.value.push(tracker);
      }
      throw e;
    } finally {
      if (track && tracker.status === "done") {
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

  /** Permanently deletes a trashed file and frees its storage. */
  async function purge(file) {
    await api.delete(`/files/${file.id}/purge`);
    items.value = items.value.filter((f) => f.id !== file.id);
    totalCount.value = Math.max(totalCount.value - 1, 0);
  }

  /** Renames a file in place. */
  async function rename(file, name) {
    const { data } = await api.patch(`/files/${file.id}`, { name });

    const index = items.value.findIndex((f) => f.id === file.id);
    if (index >= 0) items.value.splice(index, 1, data.file);

    return data.file;
  }

  /**
   * Files a picture as a document, or a document back as a picture.
   *
   * Photos and My Files are the same list with a different filter on it, so
   * changing which one a file belongs to takes it out of whichever is on
   * screen — unless the screen is a search, which spans both.
   */
  async function setFileType(file, fileType) {
    const { data } = await api.patch(`/files/${file.id}`, { file_type: fileType });

    const index = items.value.findIndex((f) => f.id === file.id);
    if (index < 0) return data.file;

    if (lastQuery.fileType && lastQuery.fileType !== fileType) {
      items.value.splice(index, 1);
      totalCount.value = Math.max(totalCount.value - 1, 0);
    } else {
      items.value.splice(index, 1, data.file);
    }

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

  /** Encrypts a file and moves it into the private section. */
  async function moveToPrivate(file, folderId = undefined) {
    const body = folderId != null ? { folder_id: folderId } : {};
    const { data } = await api.post(`/files/${file.id}/lock`, body);

    items.value = items.value.filter((f) => f.id !== file.id);
    totalCount.value = Math.max(totalCount.value - 1, 0);

    return data.file;
  }

  /** Decrypts a private file and returns it to My Files / Photos. */
  async function removeFromPrivate(file) {
    const { data } = await api.delete(`/files/${file.id}/lock`);

    items.value = items.value.filter((f) => f.id !== file.id);
    totalCount.value = Math.max(totalCount.value - 1, 0);

    return data.file;
  }

  /** Downloads several files as one ZIP (browser navigation, like folder ZIP). */
  async function downloadZip(fileIds) {
    const { data } = await api.post("/files/zip_url", { file_ids: fileIds });
    window.location.assign(data.url);
    return data;
  }

  function dismissUpload(id) {
    uploads.value = uploads.value.filter((u) => u.id !== id);
  }

  /** Merges one file into the current list without resetting pagination. */
  function upsertFile(file) {
    if (!file?.id) return;
    const idx = items.value.findIndex((f) => String(f.id) === String(file.id));
    if (idx >= 0) {
      items.value[idx] = { ...items.value[idx], ...file };
    }
  }

  return {
    items,
    uploads,
    loading,
    loadingMore,
    hasMore,
    error,
    page,
    totalPages,
    totalCount,
    hasFiles,
    isEmpty,
    fetchFiles,
    loadMore,
    upsertFile,
    upload,
    trash,
    restore,
    download,
    downloadZip,
    move,
    moveToPrivate,
    removeFromPrivate,
    rename,
    setFileType,
    purge,
    dismissUpload,
  };
});
