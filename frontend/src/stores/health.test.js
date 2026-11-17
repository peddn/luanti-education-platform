import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'

import { ApiFailure } from '@/api/client'

import { createHealthStore } from './health'

/** @typedef {import('@/api/client').Status} Status */

/** @type {Status} */
const GOOD = { status: 'ok', version: '0.1.0', mail: 'smtp' }

describe('health store', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('starts empty', () => {
    const store = createHealthStore({ status: async () => GOOD })()
    expect(store.status).toBeNull()
    expect(store.error).toBeNull()
    expect(store.loading).toBe(false)
  })

  it('keeps what the backend says', async () => {
    const store = createHealthStore({ status: async () => GOOD })()
    const loading = store.load()
    expect(store.loading).toBe(true)
    await loading
    expect(store.status).toEqual(GOOD)
    expect(store.error).toBeNull()
    expect(store.loading).toBe(false)
  })

  it('keeps the code of a failure and drops the old state', async () => {
    let fail = false
    const store = createHealthStore({
      status: async () => {
        if (fail) {
          throw new ApiFailure('network', 'fetch failed')
        }
        return GOOD
      },
    })()
    await store.load()
    fail = true
    await store.load()
    expect(store.status).toBeNull()
    expect(store.error).toBe('network')
    expect(store.loading).toBe(false)

    fail = false
    await store.load()
    expect(store.status).toEqual(GOOD)
    expect(store.error).toBeNull()
  })
})
