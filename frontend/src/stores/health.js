import { defineStore } from 'pinia'

import { api, errorCode } from '@/api/client'

/** @typedef {import('@/api/client').Status} Status */
/** @typedef {import('@/api/client').ErrorCode} ErrorCode */
/** @typedef {import('@/api/client').Client} Client */

/**
 * State of the backend with its details, for teachers who are logged in.
 *
 * @param {Pick<Client, 'status'>} [client] replaced in tests
 */
export function createHealthStore(client = api) {
  return defineStore('health', {
    state: () => ({
      status: /** @type {Status | null} */ (null),
      error: /** @type {ErrorCode | null} */ (null),
      loading: false,
    }),
    actions: {
      async load() {
        this.loading = true
        try {
          this.status = await client.status()
          this.error = null
        } catch (err) {
          this.status = null
          this.error = errorCode(err)
        } finally {
          this.loading = false
        }
      },
    },
  })
}

export const useHealthStore = createHealthStore()
