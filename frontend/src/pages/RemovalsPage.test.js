import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createLepI18n } from '@/i18n'

import RemovalsPage from './RemovalsPage.vue'

const PATH = '/api/web/v1/removals'

/** @param {[number, unknown]} answer */
function backend(answer) {
  /** @type {(path: string) => Promise<Response>} */
  const reply = async () => new Response(JSON.stringify(answer[1]), { status: answer[0] })
  const send = vi.fn(reply)
  vi.stubGlobal('fetch', send)
  return send
}

/** @param {'de' | 'en'} [language] */
async function show(language = 'de') {
  const page = mount(RemovalsPage, { global: { plugins: [createLepI18n(language)] } })
  await flushPromises()
  return page
}

describe('page of the deleted accounts', () => {
  beforeEach(() => setActivePinia(createPinia()))
  afterEach(() => vi.unstubAllGlobals())

  it('lists who deleted which account when', async () => {
    const send = backend([
      200,
      {
        removals: [
          { time: 1795105826, account: 'lustigeRobbe', group: '7b', by: 'leitung' },
          { time: 1795105818, account: 'klareEule', group: '8a' },
        ],
      },
    ])
    const page = await show()
    expect(send.mock.calls[0][0]).toBe(PATH)
    expect(page.get('h1').text()).toBe('Löschungen')
    const rows = page.findAll('[data-test=removal]').map((row) => row.findAll('td').map((cell) => cell.text()))
    expect(rows[0].slice(1)).toEqual(['lustigeRobbe', '7b', 'leitung'])
    // Deleted in the world, without an order from here.
    expect(rows[1].slice(1)).toEqual(['klareEule', '8a', 'in der Welt selbst'])
    expect(rows[0][0]).toMatch(/2026/)
    expect(page.text()).toContain('bleiben dauerhaft')
  })

  it('says so when nothing was deleted yet', async () => {
    backend([200, { removals: [] }])
    const page = await show('en')
    expect(page.get('[data-test=empty]').text()).toBe('No account has been deleted so far.')
    expect(page.find('table').exists()).toBe(false)
  })

  it('shows the refusal to who is not the school administration', async () => {
    backend([403, { code: 'forbidden', message: 'only the school administration may do this' }])
    const page = await show()
    expect(page.get('[role=alert]').text()).toContain('Das darfst du nicht.')
    expect(page.find('h1').exists()).toBe(false)
  })
})
