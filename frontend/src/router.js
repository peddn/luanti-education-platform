import { createRouter, createWebHistory } from 'vue-router'

import ConfirmPage from './pages/ConfirmPage.vue'
import GroupPage from './pages/GroupPage.vue'
import GroupsPage from './pages/GroupsPage.vue'
import StudentsPage from './pages/StudentsPage.vue'
import HealthPage from './pages/HealthPage.vue'
import LoginPage from './pages/LoginPage.vue'
import NotFoundPage from './pages/NotFoundPage.vue'
import OverviewPage from './pages/OverviewPage.vue'
import ProgressPage from './pages/ProgressPage.vue'
import ProtocolsPage from './pages/ProtocolsPage.vue'
import RemovalsPage from './pages/RemovalsPage.vue'
import YearEndPage from './pages/YearEndPage.vue'
import { useAuthStore } from './stores/auth'

// Pages are closed unless they say `public`. Without a login only the
// pages to log in and to confirm an address are shown.

/** @type {import('vue-router').RouteRecordRaw[]} */
export const routes = [
  { path: '/', name: 'overview', component: OverviewPage },
  { path: '/groups', name: 'groups', component: GroupsPage },
  { path: '/groups/:id', name: 'group', component: GroupPage, props: true },
  { path: '/groups/:id/students', name: 'students', component: StudentsPage, props: true },
  { path: '/groups/:id/progress', name: 'progress', component: ProgressPage, props: true },
  {
    path: '/groups/:id/protocols',
    name: 'protocols',
    component: ProtocolsPage,
    // The address can name where to start: a protocol and an account.
    props: (route) => ({
      id: String(route.params.id),
      startProtocol: typeof route.query.protocol === 'string' ? route.query.protocol : 'chat',
      startAccount: typeof route.query.account === 'string' ? route.query.account : '',
    }),
  },
  { path: '/year-end', name: 'yearEnd', component: YearEndPage },
  { path: '/removals', name: 'removals', component: RemovalsPage },
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
