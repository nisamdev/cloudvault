import { ref } from "vue";
import api from "@/api/client";

/**
 * The pages of a PDF, as images, fetched a batch at a time.
 *
 * A long document rendered into one response is a stalled tab and a long blank
 * screen, so the pages arrive in batches and the caller can show them as they
 * land. Shared by the tools that work page by page.
 *
 * @param {"thumb"|"render"} [size] — thumbnails for rearrange; full width for
 *   reading beside OCR text.
 */
export function usePdfPages() {
  const pages = ref([]);
  const pageCount = ref(0);
  const loading = ref(false);
  const error = ref("");

  async function load(fileId, { size = "thumb" } = {}) {
    pages.value = [];
    pageCount.value = 0;
    error.value = "";
    loading.value = true;

    try {
      let from = 1;
      for (;;) {
        const { data } = await api.get(`/files/${fileId}/pages`, {
          params: { size, from },
          timeout: 120_000,
        });

        pageCount.value = data.page_count;
        pages.value.push(...data.pages);

        if (!data.pages.length || pages.value.length >= data.page_count) break;
        from = pages.value.length + 1;
      }
    } catch (e) {
      error.value = e.userMessage;
      throw e;
    } finally {
      loading.value = false;
    }
  }

  function clear() {
    pages.value = [];
    pageCount.value = 0;
    error.value = "";
  }

  return { pages, pageCount, loading, error, load, clear };
}
