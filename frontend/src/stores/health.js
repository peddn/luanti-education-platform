import { defineStore } from 'pinia'

import { api, errorCode } from '@/api/client'

/** @typedef {import('@/api/client').Health} Health */
/** @typedef {import('@/api/client').ErrorCode} ErrorCode */
/** @typedef {import('@/api/client').Client} Client */

/**
 * State of the backend, as the health check reports it.
 *
 * @param {Pick<Client, 'health'>} [client] replaced in tests
 */
export function createHealthStore(client = api) {
  return defineStore('health', {
    state: () => ({
      health: /** @type {Health | null} */ (null),
      error: /** @type {ErrorCode | null} */ (null),
      loading: false,
    }),
    actions: {
      async load() {
        this.loading = true
        try {
          this.health = await client.health()
          this.error = null
        } catch (err) {
          this.health = null
          this.error = errorCode(err)
        } finally {
          this.loading = false
        }
      },
    },
  })
}

export const useHealthStore = createHealthStore()
