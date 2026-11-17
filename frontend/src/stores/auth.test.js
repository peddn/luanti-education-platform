import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'

import { ApiFailure } from '@/api/client'

import { createAuthStore } from './auth'

/** @typedef {import('@/api/client').Me} Me */

/** @type {Me} */
const ANNA = { account: 'lehrer1', email: 'anna@schule.example', worlds: ['7b'], expires_at: 1700043200, school_admin: false }

/**
 * A backend for the store, with a counter of the questions for "me".
 *
 * @param {Me | null} who
 */
function backend(who) {
  const state = { who, asked: 0, down: false }
  return {
    state,
    client: {
      me: async () => {
        state.asked += 1
        if (state.down) {
          throw new ApiFailure('network', 'fetch failed')
        }
        return state.who
      },
      login: async (/** @type {string} */ token) => {
        if (token !== 'lepl_good') {
          throw new ApiFailure('invalid_token', 'the token is unknown, used or too old', 400)
        }
        state.who = ANNA
        return ANNA
      },
      logout: async () => {
        if (state.down) {
          throw new ApiFailure('network', 'fetch failed')
        }
        state.who = null
      },
    },
  }
}

describe('auth store', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('asks the backend once who is logged in', async () => {
    const { client, state } = backend(ANNA)
    const store = createAuthStore(client)()
    expect(store.loggedIn).toBe(false)
    expect(store.checked).toBe(false)
    await store.load()
    await store.load()
    expect(store.me).toEqual(ANNA)
    expect(store.loggedIn).toBe(true)
    expect(state.asked).toBe(1)
  })

  it('knows when nobody is logged in', async () => {
    const store = createAuthStore(backend(null).client)()
    await store.load()
    expect(store.me).toBeNull()
    expect(store.checked).toBe(true)
  })

  it('asks again after the backend was out of reach', async () => {
    const { client, state } = backend(ANNA)
    const store = createAuthStore(client)()
    state.down = true
    await store.load()
    expect(store.loggedIn).toBe(false)
    expect(store.checked).toBe(false)
    state.down = false
    await store.load()
    expect(store.loggedIn).toBe(true)
  })

  it('logs in with a token and passes a failure on', async () => {
    const store = createAuthStore(backend(null).client)()
    await expect(store.login('lepl_old')).rejects.toMatchObject({ code: 'invalid_token' })
    expect(store.loggedIn).toBe(false)
    await store.login('lepl_good')
    expect(store.me).toEqual(ANNA)
    expect(store.checked).toBe(true)
  })

  it('forgets the teacher on logout, even without the backend', async () => {
    const { client, state } = backend(ANNA)
    const store = createAuthStore(client)()
    await store.load()
    await store.logout()
    expect(store.me).toBeNull()
    expect(state.who).toBeNull()

    await store.login('lepl_good')
    state.down = true
    await expect(store.logout()).rejects.toMatchObject({ code: 'network' })
    expect(store.me).toBeNull()
  })
})
