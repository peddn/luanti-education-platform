import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { createMemoryHistory } from 'vue-router'

import { createLepRouter, routes } from './router'
import { createAuthStore } from './stores/auth'

/** @typedef {import('@/api/client').Me} Me */

/** @type {Me} */
const ANNA = { account: 'lehrer1', email: 'anna@schule.example', worlds: ['7b'], expires_at: 1700043200 }

/**
 * @param {Me | null} who
 */
function routerFor(who) {
  let asked = 0
  const useAuth = createAuthStore({
    me: async () => {
      asked += 1
      return who
    },
    login: async () => ANNA,
    logout: async () => {},
  })
  return { router: createLepRouter(createMemoryHistory(), useAuth), asked: () => asked }
}

describe('router', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('sends everybody who is not logged in to the login', async () => {
    const { router } = routerFor(null)
    for (const path of ['/', '/status', '/no/such/page']) {
      await router.push(path)
      expect(router.currentRoute.value.name, path).toBe('login')
    }
  })

  it('shows the public pages without asking who is logged in', async () => {
    const { router, asked } = routerFor(null)
    await router.push('/login?token=lepl_abc')
    expect(router.currentRoute.value.name).toBe('login')
    expect(router.currentRoute.value.query.token).toBe('lepl_abc')
    await router.push('/confirm?token=lepc_abc')
    expect(router.currentRoute.value.name).toBe('confirm')
    expect(asked()).toBe(0)
  })

  it('lets a teacher who is logged in through', async () => {
    const { router, asked } = routerFor(ANNA)
    await router.push('/')
    expect(router.currentRoute.value.name).toBe('overview')
    await router.push('/status')
    expect(router.currentRoute.value.name).toBe('health')
    await router.push('/no/such/page')
    expect(router.currentRoute.value.name).toBe('not-found')
    expect(asked()).toBe(1)
  })

  it('opens only the pages to log in and to confirm', () => {
    const open = routes.filter((route) => route.meta?.public).map((route) => route.name)
    expect(open.sort()).toEqual(['confirm', 'login'])
  })
})
