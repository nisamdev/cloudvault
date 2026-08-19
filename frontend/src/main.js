import { createApp } from "vue";
import { createPinia } from "pinia";

import App from "./App.vue";
import router from "./router";
import { setAuthFailureHandler } from "./api/client";
import { useAuthStore } from "./stores/auth";

import "@fortawesome/fontawesome-free/css/all.min.css";
import "./assets/tokens.css";

const app = createApp(App);

app.use(createPinia());
app.use(router);

// A failed refresh means the session is over: drop state and return to sign-in.
setAuthFailureHandler(() => {
  const auth = useAuthStore();
  auth.clearSession();
  router.push({ name: "login", query: { expired: "1" } });
});

app.mount("#app");
