import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createLepI18n } from '@/i18n'

import HealthPage from './HealthPage.vue'

/**
 * @param {import('@/i18n').Locale} locale
 */
function show(locale) {
  return mount(HealthPage, { global: { plugins: [createLepI18n(locale)] } })
}

describe('health page', () => {
  beforeEach(() => setActivePinia(createPinia()))
  afterEach(() => vi.unstubAllGlobals())

  it('shows the state of the backend in German', async () => {
    vi.stubGlobal('fetch', async () =>
      new Response(JSON.stringify({ status: 'ok', version: '0.1.0', mail: 'smtp' })),
    )
    const page = show('de')
    await flushPromises()
    expect(page.get('[data-test=status]').text()).toBe('Alles in Ordnung')
    expect(page.get('[data-test=mail]').text()).toBe('über den Mailserver')
    expect(page.get('[data-test=version]').text()).toBe('0.1.0')
    expect(page.find('[role=alert]').exists()).toBe(false)
  })

  it('says that no agent is set up', async () => {
    vi.stubGlobal('fetch', async () =>
      new Response(JSON.stringify({ status: 'ok', version: '0.1.0', mail: 'smtp', game_server: null })),
    )
    const page = show('de')
    await flushPromises()
    expect(page.get('[data-test=server-none]').text()).toContain('noch kein Agent eingerichtet')
    expect(page.find('[data-test=server-state]').exists()).toBe(false)
  })

  it('shows what the agent said about the game server', async () => {
    const seen = Date.UTC(2026, 10, 20, 9, 30, 0) / 1000
    vi.stubGlobal('fetch', async () =>
      new Response(
        JSON.stringify({
          status: 'ok',
          version: '0.1.0',
          mail: 'smtp',
          game_server: { connected: true, last_seen_at: seen, version: '0.2.0', free_disk_bytes: 12_340_000_000 },
        }),
      ),
    )
    const page = show('de')
    await flushPromises()
    expect(page.get('[data-test=server-state]').text()).toBe('Verbunden')
    expect(page.get('[data-test=server-seen]').text()).toContain('2026')
    expect(page.get('[data-test=server-version]').text()).toBe('0.2.0')
    expect(page.get('[data-test=server-disk]').text()).toBe('12,3 GB')
    expect(page.find('[data-test=server-none]').exists()).toBe(false)
  })

  it('shows a game server that is out of reach or never reported', async () => {
    vi.stubGlobal('fetch', async () =>
      new Response(
        JSON.stringify({
          status: 'ok',
          version: '0.1.0',
          mail: 'smtp',
          game_server: { connected: false, last_seen_at: null, version: null, free_disk_bytes: null },
        }),
      ),
    )
    const page = show('en')
    await flushPromises()
    expect(page.get('[data-test=server-state]').text()).toBe('Out of reach')
    expect(page.get('[data-test=server-seen]').text()).toBe('never')
    expect(page.get('[data-test=server-version]').text()).toBe('unknown')
    expect(page.get('[data-test=server-disk]').text()).toBe('unknown')
  })

  it('shows the same in English', async () => {
    vi.stubGlobal('fetch', async () =>
      new Response(JSON.stringify({ status: 'degraded', version: '0.1.0', mail: 'terminal' })),
    )
    const page = show('en')
    await flushPromises()
    expect(page.get('[data-test=status]').text()).toBe('Limited')
    expect(page.get('[data-test=mail]').text()).toContain('not set up')
  })

  it('translates the code of a failure', async () => {
    vi.stubGlobal('fetch', async () =>
      new Response(JSON.stringify({ code: 'internal', message: 'the backend could not do this' }), {
        status: 500,
      }),
    )
    const page = show('de')
    await flushPromises()
    const note = page.get('[role=alert]').text()
    expect(note).toContain('Im Backend ist ein Fehler aufgetreten.')
    expect(note).not.toContain('the backend could not do this')
    expect(page.find('[data-test=status]').exists()).toBe(false)
  })

  it('says when the backend is out of reach', async () => {
    vi.stubGlobal('fetch', async () => {
      throw new TypeError('fetch failed')
    })
    const page = show('en')
    await flushPromises()
    expect(page.get('[role=alert]').text()).toContain('The backend cannot be reached.')
  })
})
