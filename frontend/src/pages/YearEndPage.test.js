import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createMemoryHistory } from 'vue-router'

import { createLepI18n } from '@/i18n'
import { createLepRouter } from '@/router'

import YearEndPage from './YearEndPage.vue'

const PATH = '/api/web/v1/year-end'

/**
 * @param {Record<string, unknown>} [first] changes to the first group
 * @param {unknown[]} [runs]
 */
function overview(first = {}, runs = []) {
  return {
    groups: [
      { id: 'id-7b', name: '7b', protocol_entries: 120, exports: 2, ...first },
      { id: 'id-8a', name: '8a', protocol_entries: 0, exports: 0 },
    ],
    runs,
  }
}

/**
 * A backend that answers by method and path. An answer can be a function
 * that is asked every time.
 *
 * @param {Record<string, [number, unknown] | (() => [number, unknown])>} answers
 */
function backend(answers) {
  /** @type {(path: string, init?: RequestInit) => Promise<Response>} */
  const answer = async (path, init) => {
    const found = answers[`${init?.method ?? 'GET'} ${path}`]
    const [status, body] =
      (typeof found === 'function' ? found() : found) ?? [404, { code: 'not_found', message: 'no such path' }]
    return new Response(JSON.stringify(body), { status })
  }
  const send = vi.fn(answer)
  vi.stubGlobal('fetch', send)
  return send
}

async function show() {
  const router = createLepRouter(createMemoryHistory())
  await router.push('/login')
  await router.isReady()
  const page = mount(YearEndPage, { global: { plugins: [router, createLepI18n('de')] } })
  await flushPromises()
  return page
}

/** @param {ReturnType<typeof backend>} send */
function posted(send) {
  return send.mock.calls.filter(([, init]) => init?.method === 'POST').map(([, init]) => JSON.parse(String(init?.body)))
}

describe('year end page', () => {
  beforeEach(() => setActivePinia(createPinia()))
  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
  })

  it('shows what would be deleted and what stays', async () => {
    backend({ [`GET ${PATH}`]: [200, overview()] })
    const page = await show()
    expect(page.get('h1').text()).toBe('Jahresabschluss')
    expect(page.text()).toContain('Alle Protokolle aller Gruppen')
    expect(page.text()).toContain('Konten, Fortschritt, Trophäen und Wunschnamen')
    expect(page.text()).toContain('Archivierte Welten und Sicherungen gibt es noch nicht')
    const rows = page.findAll('[data-test=group]')
    expect(rows.map((row) => row.findAll('td').map((cell) => cell.text()))).toEqual([
      ['7bProtokolle ansehen und exportieren', '120', '2', ''],
      ['8aProtokolle ansehen und exportieren', '0', '0', ''],
    ])
    // What is needed can be exported before: the way leads to the protocols.
    expect(rows[0].get('a').attributes('href')).toBe('/groups/id-7b/protocols')
    expect(page.text()).toContain('Es gab noch keinen.')
    expect(page.find('[data-test=done]').exists()).toBe(false)
  })

  it('closes the year only after the word was typed', async () => {
    const send = backend({
      [`GET ${PATH}`]: [200, overview()],
      [`POST ${PATH}`]: [
        200,
        overview({ protocol_entries: 0, exports: 0, world: 'pending' }, [
          { time: 1700000000, account: 'leitung', groups: 2, protocol_entries: 120, exports: 2 },
        ]),
      ],
    })
    const page = await show()
    const button = page.get('[data-test=close]')
    expect(button.attributes('disabled')).toBeDefined()
    expect(page.text()).toContain('Tippe zur Bestätigung das Wort LÖSCHEN')

    // Sent with the enter key, past the button that is switched off.
    await page.get('input[name=confirm]').setValue('löschen')
    await page.get('form').trigger('submit')
    await flushPromises()
    expect(button.attributes('disabled')).toBeDefined()
    expect(posted(send)).toEqual([])

    await page.get('input[name=confirm]').setValue(' LÖSCHEN ')
    expect(button.attributes('disabled')).toBeUndefined()
    await page.get('form').trigger('submit')
    await flushPromises()
    expect(posted(send)).toEqual([{ confirm: 'close-the-year' }])

    expect(page.get('[data-test=done]').text()).toContain('Das Jahr ist abgeschlossen')
    const first = page.findAll('[data-test=group]')[0].findAll('td')
    expect(first[1].text()).toBe('0')
    expect(first[3].text()).toBe('hat ihre Protokolle noch nicht gelöscht')
    expect(page.get('[data-test=run]').text()).toContain(
      'durch leitung, 120 Einträge in Protokollen und 2 in der Exportliste gelöscht, 2 Gruppen',
    )
    // The word has to be typed again for another time.
    expect(/** @type {HTMLInputElement} */ (page.get('input[name=confirm]').element).value).toBe('')
    expect(page.get('[data-test=close]').attributes('disabled')).toBeDefined()
  })

  it('asks again while a world has not deleted, and stops when all have', async () => {
    vi.useFakeTimers()
    let world = /** @type {string | undefined} */ ('pending')
    const send = backend({ [`GET ${PATH}`]: () => [200, overview({ world })] })
    const page = await show()
    expect(send).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(3100)
    expect(send).toHaveBeenCalledTimes(2)

    world = undefined
    await vi.advanceTimersByTimeAsync(3100)
    await flushPromises()
    expect(send).toHaveBeenCalledTimes(3)
    expect(page.findAll('[data-test=group]')[0].findAll('td')[3].text()).toBe('')
    await vi.advanceTimersByTimeAsync(10000)
    expect(send).toHaveBeenCalledTimes(3)

    page.unmount()
    world = 'pending'
    await vi.advanceTimersByTimeAsync(10000)
    expect(send).toHaveBeenCalledTimes(3)
  })

  it('says when a world could not delete', async () => {
    backend({ [`GET ${PATH}`]: [200, overview({ world: 'refused' })] })
    const page = await show()
    const cell = page.findAll('[data-test=group]')[0].findAll('td')[3]
    expect(cell.text()).toBe('konnte ihre Protokolle nicht löschen')
    expect(cell.classes()).toContain('text-red-800')
  })

  it('shows a failure and deletes nothing in the page', async () => {
    backend({
      [`GET ${PATH}`]: [200, overview()],
      [`POST ${PATH}`]: [403, { code: 'forbidden', message: 'not for you' }],
    })
    const page = await show()
    await page.get('input[name=confirm]').setValue('LÖSCHEN')
    await page.get('form').trigger('submit')
    await flushPromises()
    expect(page.text()).toContain('Das darfst du nicht.')
    expect(page.findAll('[data-test=group]')[0].findAll('td')[1].text()).toBe('120')
    expect(page.find('[data-test=done]').exists()).toBe(false)
  })

  it('is not for teachers who are not the school administration', async () => {
    backend({ [`GET ${PATH}`]: [403, { code: 'forbidden', message: 'not for you' }] })
    const page = await show()
    expect(page.text()).toContain('Das darfst du nicht.')
    expect(page.find('form').exists()).toBe(false)
  })
})
