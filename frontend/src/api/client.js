import axios from "axios";

/**
 * Runtime configuration.
 *
 * Read from window.__CLOUDVAULT_CONFIG__ (written by the container entrypoint)
 * rather than import.meta.env, so the same built image works in every
 * environment. VITE_API_URL is only a fallback for `npm run dev` outside Docker.
 */
export const runtimeConfig = {
  apiUrl:
    window.__CLOUDVAULT_CONFIG__?.apiUrl ??
    import.meta.env.VITE_API_URL ??
    "",
  appEnv: window.__CLOUDVAULT_CONFIG__?.appEnv ?? import.meta.env.MODE,
};

// Empty apiUrl means same-origin: the dev server proxies /api, and in production
// nginx and the API can sit behind one domain.
const baseURL = `${runtimeConfig.apiUrl}/api/v1`.replace(/([^:]\/)\/+/g, "$1");

const api = axios.create({
  baseURL,
  timeout: 30_000,
  // Refresh token lives in an httpOnly cookie; it must ride along.
  withCredentials: true,
  headers: { Accept: "application/json" },
});

/*
 * Access token is held in memory only.
 *
 * PHASE1_IMPLEMENTATION_GUIDE.md's example store puts it in localStorage, but
 * that hands the token to any XSS on the page. The refresh token is an httpOnly
 * cookie the browser sends automatically, so a page reload recovers the session
 * without persisting the access token anywhere scriptable.
 */
let accessToken = null;
let onAuthFailure = () => {};

export function setAccessToken(token) {
  accessToken = token;
}

export function getAccessToken() {
  return accessToken;
}

export function setAuthFailureHandler(handler) {
  onAuthFailure = handler;
}

api.interceptors.request.use((config) => {
  if (accessToken) {
    config.headers.Authorization = `Bearer ${accessToken}`;
  }
  return config;
});

/*
 * Single-flight refresh: if several requests 401 at once, they all wait on one
 * refresh call instead of firing a stampede (and racing to replace the token).
 */
let refreshPromise = null;

function refreshAccessToken() {
  refreshPromise ??= api
    .post("/auth/refresh", {}, { _skipAuthRetry: true })
    .then((response) => {
      const token = response.data.access_token;
      setAccessToken(token);
      return token;
    })
    .finally(() => {
      refreshPromise = null;
    });

  return refreshPromise;
}

api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const { config, response } = error;

    if (
      response?.status === 401 &&
      config &&
      !config._retried &&
      !config._skipAuthRetry &&
      // The refresh endpoint itself 401ing means the session is genuinely over.
      !config.url?.includes("/auth/refresh")
    ) {
      config._retried = true;
      try {
        await refreshAccessToken();
        return api(config);
      } catch {
        setAccessToken(null);
        onAuthFailure();
      }
    }

    return Promise.reject(normalizeError(error));
  },
);

/**
 * Give the UI one error shape to render, whatever went wrong.
 * The API returns { error: { message, code, details } } on failure.
 */
function normalizeError(error) {
  const payload = error.response?.data?.error;

  return Object.assign(error, {
    userMessage:
      payload?.message ??
      (error.code === "ECONNABORTED"
        ? "The request timed out. Please try again."
        : error.response
          ? "Something went wrong. Please try again."
          : "Cannot reach CloudVault. Check your connection."),
    fieldErrors: payload?.details ?? {},
    status: error.response?.status ?? 0,
  });
}

export default api;
