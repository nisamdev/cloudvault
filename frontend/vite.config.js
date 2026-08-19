import { fileURLToPath, URL } from "node:url";
import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import tailwindcss from "@tailwindcss/vite";

// https://vite.dev/config/
export default defineConfig({
  plugins: [vue(), tailwindcss()],

  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },

  server: {
    host: "0.0.0.0",
    port: Number(process.env.PORT) || 5173,
    // Bind mounts in Docker don't emit inotify events reliably on WSL2.
    watch: { usePolling: true, interval: 300 },
    // Same-origin /api in dev means no CORS preflight and no cookie/SameSite
    // surprises. VITE_PROXY_TARGET is the api service inside compose.
    proxy: {
      "/api": {
        target: process.env.VITE_PROXY_TARGET || "http://localhost:3100",
        changeOrigin: true,
      },
    },
  },

  build: {
    // Sourcemaps make production stack traces readable; they cost build time,
    // not runtime.
    sourcemap: true,
    rollupOptions: {
      output: {
        // Keep dependencies in one stable chunk so it stays cached across
        // deploys. Vite 8 / Rolldown only accepts the function form here.
        manualChunks(id) {
          if (id.includes("node_modules")) return "vendor";
          return null;
        },
      },
    },
  },

  test: {
    environment: "jsdom",
    globals: true,
  },
});
