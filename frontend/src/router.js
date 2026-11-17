import { createRouter, createWebHistory } from 'vue-router'

import ConfirmPage from './pages/ConfirmPage.vue'
import GroupPage from './pages/GroupPage.vue'
import GroupsPage from './pages/GroupsPage.vue'
import HealthPage from './pages/HealthPage.vue'
import LoginPage from './pages/LoginPage.vue'
import NotFoundPage from './pages/NotFoundPage.vue'
import OverviewPage from './pages/OverviewPage.vue'
import { useAuthStore } from './stores/auth'

// Pages are closed unless they say `public`. Without a login only the
// pages to log in and to confirm an address are shown.

/** @type {import('vue-router').RouteRecordRaw[]} */
export const routes = [
  { path: '/', name: 'overview', component: OverviewPage },
  { path: '/groups', name: 'groups', component: GroupsPage },
  { path: '/groups/:id', name: 'group', component: GroupPage, props: true },
  { path: '/status', name: 'health', component: HealthPage },
  { path: '/login', name: 'login', component: LoginPage, meta: { public: true } },
  { path: '/confirm', name: 'confirm', component: ConfirmPage, meta: { public: true } },
  { path: '/:rest(.*)*', name: 'not-found', component: NotFoundPage },
]

/**
 * @param {import('vue-router').RouterHistory} [history]
 * @param {typeof useAuthStore} [useAuth] replaced in tests
 */
export function createLepRouter(history = createWebHistory(), useAuth = useAuthStore) {
  const router = createRouter({ history, routes })

  router.beforeEach(async (to) => {
    if (to.meta.public) {
      return true
    }
    const auth = useAuth()
    await auth.load()
    if (!auth.loggedIn) {
      return { name: 'login' }
    }
    return true
  })

  return router
}
