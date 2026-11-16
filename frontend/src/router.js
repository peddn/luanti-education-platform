import { createRouter, createWebHistory } from 'vue-router'

import HealthPage from './pages/HealthPage.vue'
import NotFoundPage from './pages/NotFoundPage.vue'

/** @type {import('vue-router').RouteRecordRaw[]} */
export const routes = [
  { path: '/', name: 'health', component: HealthPage },
  { path: '/:rest(.*)*', name: 'not-found', component: NotFoundPage },
]

/**
 * @param {import('vue-router').RouterHistory} [history]
 */
export function createLepRouter(history = createWebHistory()) {
  return createRouter({ history, routes })
}
