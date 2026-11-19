import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createMemoryHistory } from 'vue-router'

import { createLepI18n } from '@/i18n'
import { createLepRouter } from '@/router'
import { useAuthStore } from '@/stores/auth'
import { fakeEventSource, settled } from '@/test/fakeEventSource'

import ProtocolsPage from './ProtocolsPage.vue'

const GROUP = { id: 'id-7b', name: '7b', teachers: ['lehrer1'] }
const BASE = '/api/web/v1/groups/id-7b'
const STUDENTS = { students: [{ account: 'klugeEule', state: 'active' }, { account: 'stillerBach', state: 'draft' }] }

/**
 * @param {number} id
 * @param {string} text
 * @param {Record<string, unknown>} [changes]
 */
function chat(id, text, changes = {}) {
  return { id, time: 1700000000 + id * 60, account: 'klugeEule', fields: { kind: 'chat', text }, ...changes }
}

/**
 * @param {unknown[]} entries
 * @param {boolean} [more]
 */
function page(entries, more = false) {
  return { columns: ['kind', 'recipient', 'text'], entries, more }
}

/**
 * A backend that answers by path, with the query. An answer can be a
 * function that is asked every time.
 *
 * @param {Record<string, [number, unknown] | (() => [number, unknown])>} answers
 */
function backend(answers) {
  /** @type {(path: string) => Promise<Response>} */
  const answer = async (path) => {
    const found = answers[path]
    const [status, body] =
      (typeof found === 'function' ? found() : found) ?? [404, { code: 'not_found', message: 'no such path' }]
    return new Response(JSON.stringify(body), { status })
  }
  const send = vi.fn(answer)
  vi.stubGlobal('fetch', send)
  return send
}

/**
 * @param {{ schoolAdmin?: boolean, startProtocol?: string, startAccount?: string }} [options]
 */
async function show({ schoolAdmin = false, startProtocol, startAccount } = {}) {
  const auth = useAuthStore()
  auth.me = {
    account: 'lehrer1',
    email: 'anna@schule.example',
    worlds: ['7b'],
    expires_at: 1700043200,
    school_admin: schoolAdmin,
  }
  const router = createLepRouter(createMemoryHistory())
  await router.push('/login')
  await router.isReady()
  const mounted = mount(ProtocolsPage, {
    props: { id: 'id-7b', startProtocol, startAccount },
    global: { plugins: [router, createLepI18n('de')] },
  })
  await flushPromises()
  return mounted
}

/** @param {import('@vue/test-utils').VueWrapper} mounted */
function texts(mounted) {
  return mounted.findAll('[data-test=entry]').map((row) => row.findAll('td').at(-1)?.text())
}

/** @param {ReturnType<typeof backend>} send */
function asked(send) {
  return send.mock.calls.map(([path]) => String(path)).filter((path) => path.includes('/protocols/'))
}

describe('protocols page', () => {
  beforeEach(() => setActivePinia(createPinia()))
  afterEach(() => vi.unstubAllGlobals())

  it('shows the chat of the group, newest first, with fixed words translated', async () => {
    backend({
      [BASE]: [200, GROUP],
      [`${BASE}/students`]: [200, STUDENTS],
      [`${BASE}/protocols/chat`]: [
        200,
        page([
          chat(2, 'geheim', { fields: { kind: 'private', recipient: 'frohesReh', text: 'geheim' } }),
          chat(1, 'hallo', { display_name: 'Lena' }),
        ]),
      ],
    })
    const mounted = await show()
    expect(mounted.get('h1').text()).toBe('Protokolle der Gruppe 7b')
    expect(mounted.findAll('th').map((head) => head.text())).toEqual(['Zeit', 'Konto', 'Art', 'An', 'Text'])
    const rows = mounted.findAll('[data-test=entry]')
    expect(rows[0].findAll('td').map((cell) => cell.text())).toEqual([
      expect.stringContaining('14.11.2023'),
      'klugeEule',
      'privat',
      'frohesReh',
      'geheim',
    ])
    // The account as it is stored, the display name of today below it.
    expect(rows[1].findAll('td')[1].text()).toBe('klugeEuleLena')
    expect(rows[1].findAll('td')[2].text()).toBe('an alle')
    // Only accounts that exist are offered for the filter.
    expect(mounted.findAll('datalist option').map((option) => option.attributes('value'))).toEqual(['klugeEule'])
    expect(mounted.find('[data-test=more]').exists()).toBe(false)
    expect(mounted.find('[data-test=waiting]').exists()).toBe(false)
  })

  it('offers the protocol of the desk to the school administration only', async () => {
    const answers = {
      [BASE]: /** @type {[number, unknown]} */ ([200, GROUP]),
      [`${BASE}/students`]: /** @type {[number, unknown]} */ ([200, STUDENTS]),
      [`${BASE}/protocols/chat`]: /** @type {[number, unknown]} */ ([200, page([])]),
      [`${BASE}/protocols/desk`]: /** @type {[number, unknown]} */ ([
        200,
        { columns: ['action', 'targets'], entries: [], more: false },
      ]),
    }
    backend(answers)
    let mounted = await show()
    const tabs = () => mounted.findAll('[data-test=tab]').map((tab) => tab.text())
    expect(tabs()).toEqual(['Chat', 'Schilder', 'Belohnungen', 'Wunschnamen'])
    // Not through the address either.
    const send = backend(answers)
    mounted = await show({ startProtocol: 'desk' })
    expect(asked(send)).toEqual([`${BASE}/protocols/chat`])

    backend(answers)
    mounted = await show({ schoolAdmin: true })
    expect(tabs()).toEqual(['Chat', 'Schilder', 'Belohnungen', 'Wunschnamen', 'Lehrerpult'])
  })

  it('switches between protocols and shows their own columns', async () => {
    const send = backend({
      [BASE]: [200, GROUP],
      [`${BASE}/students`]: [200, STUDENTS],
      [`${BASE}/protocols/chat`]: [200, page([chat(1, 'hallo')])],
      [`${BASE}/protocols/rewards`]: [
        200,
        {
          columns: ['size', 'reason', 'module', 'level', 'task', 'items'],
          entries: [
            {
              id: 9,
              time: 1700000000,
              account: 'klugeEule',
              fields: { size: 'medium', reason: 'level', module: 'lep_math:math', level: '2', items: 'default:gold_ingot 1' },
            },
          ],
          more: false,
        },
      ],
    })
    const mounted = await show()
    await mounted.findAll('[data-test=tab]')[2].trigger('click')
    await flushPromises()
    expect(asked(send).at(-1)).toBe(`${BASE}/protocols/rewards`)
    expect(mounted.findAll('th').map((head) => head.text())).toEqual([
      'Zeit',
      'Konto',
      'Größe',
      'Anlass',
      'Modul',
      'Niveau',
      'Aufgabe',
      'Gegenstände',
    ])
    const cells = mounted.get('[data-test=entry]').findAll('td')
    expect(cells.slice(2).map((cell) => cell.text())).toEqual([
      'mittel',
      'Niveau abgeschlossen',
      'lep_math:math',
      '2',
      '',
      'default:gold_ingot 1',
    ])
    expect(mounted.findAll('[data-test=tab]')[2].attributes('aria-pressed')).toBe('true')
  })

  it('narrows down by account and period, also for the export', async () => {
    vi.useFakeTimers({ toFake: ['Date'], now: new Date('2023-11-20T12:00:00Z') })
    const week = 1700481600 - 7 * 86400
    const send = backend({
      [BASE]: [200, GROUP],
      [`${BASE}/students`]: [200, STUDENTS],
      [`${BASE}/protocols/chat?account=klugeEule`]: [200, page([chat(1, 'von der Eule')])],
      [`${BASE}/protocols/chat?account=klugeEule&since=${week}`]: [200, page([])],
    })
    // The address names the account, as the link in the list of students does.
    const mounted = await show({ startAccount: 'klugeEule' })
    expect(texts(mounted)).toEqual(['von der Eule'])
    expect(mounted.get('[data-test=export]').attributes('href')).toBe(
      `${BASE}/protocols/chat/export?account=klugeEule`,
    )

    await mounted.get('select[name=period]').setValue('week')
    await flushPromises()
    expect(asked(send).at(-1)).toBe(`${BASE}/protocols/chat?account=klugeEule&since=${week}`)
    expect(mounted.get('[data-test=empty]').text()).toBe('Es gibt keine Einträge, die dazu passen.')
    expect(mounted.get('[data-test=export]').attributes('href')).toBe(
      `${BASE}/protocols/chat/export?account=klugeEule&since=${week}`,
    )
    expect(mounted.text()).toContain('verlässt die Plattform')
    vi.useRealTimers()
  })

  it('loads older entries below the ones that are shown', async () => {
    const send = backend({
      [BASE]: [200, GROUP],
      [`${BASE}/students`]: [200, STUDENTS],
      [`${BASE}/protocols/chat`]: [200, page([chat(3, 'drei'), chat(2, 'zwei')], true)],
      [`${BASE}/protocols/chat?before=2`]: [200, page([chat(1, 'eins')])],
    })
    const mounted = await show()
    await mounted.get('[data-test=more]').trigger('click')
    await flushPromises()
    expect(asked(send).at(-1)).toBe(`${BASE}/protocols/chat?before=2`)
    expect(texts(mounted)).toEqual(['drei', 'zwei', 'eins'])
    expect(mounted.find('[data-test=more]').exists()).toBe(false)
  })

  it('stays quiet when entries arrive and shows them on a click', async () => {
    const opened = fakeEventSource()
    const send = backend({
      [BASE]: [200, GROUP],
      [`${BASE}/students`]: [200, STUDENTS],
      [`${BASE}/protocols/chat`]: [200, page([chat(1, 'eins')])],
      [`${BASE}/protocols/chat?after=1`]: [200, page([chat(3, 'drei'), chat(2, 'zwei')])],
      [`${BASE}/protocols/chat?after=3`]: [200, page([chat(4, 'vier')])],
    })
    const mounted = await show()
    expect(opened.map((source) => source.url)).toEqual([`${BASE}/changes`])

    // Other parts of the group are none of this page's business.
    opened[0].change('progress')
    await settled()
    expect(asked(send)).toHaveLength(1)

    opened[0].change('protocols')
    await settled()
    await flushPromises()
    // The lines do not move while somebody reads.
    expect(texts(mounted)).toEqual(['eins'])
    expect(mounted.get('[data-test=waiting]').text()).toBe('2 neue Einträge anzeigen')

    // More arrive: asked from the newest that is waiting.
    opened[0].change('protocols')
    await settled()
    await flushPromises()
    expect(asked(send).at(-1)).toBe(`${BASE}/protocols/chat?after=3`)
    expect(mounted.get('[data-test=waiting]').text()).toBe('3 neue Einträge anzeigen')

    await mounted.get('[data-test=waiting]').trigger('click')
    expect(texts(mounted)).toEqual(['vier', 'drei', 'zwei', 'eins'])
    expect(mounted.find('[data-test=waiting]').exists()).toBe(false)
  })

  it('shows a failure and keeps what was loaded', async () => {
    let down = false
    backend({
      [BASE]: [200, GROUP],
      [`${BASE}/students`]: [200, STUDENTS],
      [`${BASE}/protocols/chat`]: () =>
        down ? [403, { code: 'forbidden', message: 'not for you' }] : [200, page([chat(1, 'eins')])],
    })
    const mounted = await show()
    down = true
    await mounted.get('form').trigger('submit')
    await flushPromises()
    expect(mounted.text()).toContain('Das darfst du nicht.')
    expect(texts(mounted)).toEqual(['eins'])
  })

  it('shows a foreign group as not found', async () => {
    backend({})
    const mounted = await show()
    expect(mounted.text()).toContain('Das gibt es nicht.')
    expect(mounted.find('table').exists()).toBe(false)
  })
})
