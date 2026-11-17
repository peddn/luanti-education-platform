import { defineStore } from 'pinia'

import { api } from '@/api/client'

/** @typedef {import('@/api/client').Me} Me */
/** @typedef {import('@/api/client').Client} Client */

/**
 * Who is logged in. The session itself is a cookie the page cannot read;
 * the backend says who it belongs to.
 *
 * @param {Pick<Client, 'me' | 'login' | 'logout'>} [client] replaced in tests
 */
export function createAuthStore(client = api) {
  return defineStore('auth', {
    state: () => ({
      me: /** @type {Me | null} */ (null),
      // True once the backend was asked who is logged in.
      checked: false,
    }),
    getters: {
      loggedIn: (state) => state.me !== null,
    },
    actions: {
      /**
       * Asks the backend who is logged in, once. A failure counts as
       * nobody for now and is asked again the next time.
       */
      async load() {
        if (this.checked) {
          return
        }
        try {
          this.me = await client.me()
          this.checked = true
        } catch {
          this.me = null
        }
      },

      /**
       * Logs in with the token from a login mail.
       *
       * @param {string} token
       */
      async login(token) {
        this.me = await client.login(token)
        this.checked = true
      },

      /** Logs out. The page forgets the teacher even if the backend is out of reach. */
      async logout() {
        try {
          await client.logout()
        } finally {
          this.forget()
        }
      },

      /** Notes that nobody is logged in any more. */
      forget() {
        this.me = null
        this.checked = true
      },
    },
  })
}

export const useAuthStore = createAuthStore()
