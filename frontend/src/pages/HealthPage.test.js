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
      new Response(JSON.stringify({ status: 'ok', version: '0.1.0', database: true })),
    )
    const page = show('de')
    await flushPromises()
    expect(page.get('[data-test=status]').text()).toBe('Alles in Ordnung')
    expect(page.get('[data-test=database]').text()).toBe('antwortet')
    expect(page.get('[data-test=version]').text()).toBe('0.1.0')
    expect(page.find('[role=alert]').exists()).toBe(false)
  })

  it('shows the same in English', async () => {
    vi.stubGlobal('fetch', async () =>
      new Response(JSON.stringify({ status: 'degraded', version: '0.1.0', database: false })),
    )
    const page = show('en')
    await flushPromises()
    expect(page.get('[data-test=status]').text()).toBe('Limited')
    expect(page.get('[data-test=database]').text()).toBe('does not answer')
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
