import { createRouter, createWebHistory } from "vue-router";
import { useAuthStore } from "@/stores/auth";

/**
 * Routes mirror the screens in docs/cloudvault_ui_prototype.html.
 * Views are lazy-loaded so the auth screens don't pull in the whole app.
 */
const routes = [
  {
    path: "/login",
    name: "login",
    component: () => import("@/views/LoginView.vue"),
    meta: { public: true, title: "Sign in" },
  },
  {
    path: "/register",
    name: "register",
    component: () => import("@/views/RegisterView.vue"),
    meta: { public: true, title: "Create account" },
  },
  {
    // Public share links must work without an account.
    path: "/share/:token",
    name: "public-share",
    component: () => import("@/views/PublicShareView.vue"),
    meta: { public: true, title: "Shared with you" },
  },
  {
    // Phone capture page. Public: the token in the URL is the credential, and
    // the phone is deliberately not signed in.
    path: "/scan/:token",
    name: "scan",
    component: () => import("@/views/ScanView.vue"),
    meta: { public: true, title: "Scan to CloudVault" },
  },
  {
    // Target of the invitation email link. Public: the recipient may not have
    // an account yet.
    path: "/invitations/:token",
    name: "accept-invitation",
    component: () => import("@/views/AcceptInvitationView.vue"),
    meta: { public: true, title: "Join a family" },
  },
  {
    path: "/family/setup",
    name: "family-setup",
    component: () => import("@/views/FamilySetupView.vue"),
    meta: { title: "Set up your family" },
  },
  {
    path: "/",
    component: () => import("@/components/layout/AppLayout.vue"),
    children: [
      {
        path: "",
        name: "dashboard",
        component: () => import("@/views/DashboardView.vue"),
        meta: { title: "My Files" },
      },
      {
        path: "images",
        name: "images",
        component: () => import("@/views/ImagesView.vue"),
        meta: { title: "Photo Gallery" },
      },
      {
        path: "shared",
        name: "shared",
        component: () => import("@/views/SharedView.vue"),
        meta: { title: "Shared" },
      },
      {
        path: "trash",
        name: "trash",
        component: () => import("@/views/TrashView.vue"),
        meta: { title: "Trash" },
      },
      {
        path: "settings",
        name: "settings",
        component: () => import("@/views/SettingsView.vue"),
        meta: { title: "Settings" },
      },
    ],
  },
  {
    path: "/:pathMatch(.*)*",
    name: "not-found",
    component: () => import("@/views/NotFoundView.vue"),
    meta: { public: true, title: "Page not found" },
  },
];

const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: (to, from, savedPosition) => savedPosition ?? { top: 0 },
});

router.beforeEach(async (to) => {
  const auth = useAuthStore();

  // On a hard reload the access token is gone (it lives in memory only), but the
  // refresh cookie may still be valid — try once before deciding it's a guest.
  if (!auth.isAuthenticated && !auth.sessionChecked) {
    await auth.restoreSession();
  }

  if (!to.meta.public && !auth.isAuthenticated) {
    return { name: "login", query: { redirect: to.fullPath } };
  }

  // A signed-in user has no business on the sign-in screen.
  if (auth.isAuthenticated && (to.name === "login" || to.name === "register")) {
    return { name: "dashboard" };
  }

  return true;
});

// ACCESSIBILITY.md: announce the new page title after client-side navigation,
// since screen readers don't re-announce on route change.
router.afterEach((to) => {
  document.title = to.meta.title ? `${to.meta.title} · CloudVault` : "CloudVault";
});

export default router;
