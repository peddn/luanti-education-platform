import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createMemoryHistory } from 'vue-router'

import { createLepI18n } from '@/i18n'
import { createLepRouter } from '@/router'
import { fakeEventSource, settled } from '@/test/fakeEventSource'

import ProgressPage from './ProgressPage.vue'

const GROUP = { id: 'id-7b', name: '7b', teachers: ['lehrer1'] }
const BASE = '/api/web/v1/groups/id-7b'
const MATH = { id: 'lep_math:math', title: 'Kopfrechnen', levels: 3, start_level: 1 }
const CELL_PATH = `${BASE}/progress/klugeEule/lep_math%3Amath`

/**
 * @param {Record<string, unknown>} [changes]
 */
function cell(changes = {}) {
  return {
    module: MATH.id,
    started: true,
    level: 2,
    locked: false,
    percent: 40,
    completed: false,
    tasks: [
      { title: 'Addieren bis 100', solved: 2, required: 5 },
      { title: 'Subtrahieren bis 100', solved: 0, required: 5 },
    ],
    ...changes,
  }
}

/**
 * @param {Record<string, unknown>} [first] changes to the cell of the first student
 */
function progress(first = {}) {
  return {
    modules: [MATH],
    students: [
      {
        account: 'klugeEule',
        display_name: 'Lena',
        modules: [cell(first)],
        trophies: [{ title: 'Rechenpokal', material: 'silver' }],
      },
      {
        account: 'frohesReh',
        modules: [cell({ started: false, level: 1, percent: 0, tasks: [] })],
        trophies: [],
      },
    ],
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
  const page = mount(ProgressPage, {
    props: { id: 'id-7b' },
    global: { plugins: [router, createLepI18n('de')] },
  })
  await flushPromises()
  return page
}

/**
 * The bodies of the requests that ordered a change.
 *
 * @param {ReturnType<typeof backend>} send
 */
function ordered(send) {
  return send.mock.calls
    .filter(([path, init]) => path === CELL_PATH && init?.method === 'POST')
    .map(([, init]) => JSON.parse(String(init?.body)))
}

describe('progress page', () => {
  beforeEach(() => setActivePinia(createPinia()))
  afterEach(() => vi.unstubAllGlobals())

  describe('start level', () => {
    const START = `${BASE}/progress/start/lep_math%3Amath`

    /** @param {Record<string, unknown>} module changes to the module */
    function withModule(module) {
      return { ...progress(), modules: [{ ...MATH, ...module }] }
    }

    it('shows the start level of each module and orders another one', async () => {
      const send = backend({
        [`GET ${BASE}`]: [200, GROUP],
        [`GET ${BASE}/progress`]: [200, progress()],
        [`POST ${START}`]: [200, withModule({ start_change: 'pending' })],
      })
      const page = await show()
      const row = page.get('[data-test=start-level]')
      expect(row.text()).toContain('Kopfrechnen')
      const select = row.get('select')
      expect(/** @type {HTMLSelectElement} */ (select.element).value).toBe('1')
      expect(row.findAll('option').map((option) => option.text())).toEqual([
        'Niveau 1 von 3',
        'Niveau 2 von 3',
        'Niveau 3 von 3',
      ])
      expect(page.text()).toContain('weder Belohnung noch Trophäe')

      await select.setValue('3')
      await flushPromises()
      const [, init] = send.mock.calls.find(([path]) => path === START) ?? []
      expect(JSON.parse(String(init?.body))).toEqual({ level: 3 })
      // The world has not answered: the old level counts, and nothing
      // else can be ordered meanwhile.
      const waiting = page.get('[data-test=start-level]')
      expect(waiting.get('[data-test=start-change]').text()).toBe('Änderung wartet auf die Welt')
      expect(/** @type {HTMLSelectElement} */ (waiting.get('select').element).value).toBe('1')
      expect(waiting.get('select').attributes('disabled')).toBeDefined()
    })

    it('shows the new level once the world has reported it', async () => {
      const opened = fakeEventSource()
      let answer = withModule({ start_change: 'pending' })
      backend({ [`GET ${BASE}`]: [200, GROUP], [`GET ${BASE}/progress`]: () => [200, answer] })
      const page = await show()
      answer = withModule({ start_level: 3 })
      opened[0].change('progress')
      await settled()
      await flushPromises()
      const row = page.get('[data-test=start-level]')
      expect(/** @type {HTMLSelectElement} */ (row.get('select').element).value).toBe('3')
      expect(row.find('[data-test=start-change]').exists()).toBe(false)
    })

    it('says so when the world refused, and lets it be tried again', async () => {
      backend({
        [`GET ${BASE}`]: [200, GROUP],
        [`GET ${BASE}/progress`]: [200, withModule({ start_change: 'refused' })],
      })
      const page = await show()
      const row = page.get('[data-test=start-level]')
      expect(row.get('[data-test=start-change]').text()).toBe('Änderung von der Welt abgelehnt')
      expect(row.get('select').attributes('disabled')).toBeUndefined()
    })

    it('can be set before there are students', async () => {
      backend({
        [`GET ${BASE}`]: [200, GROUP],
        [`GET ${BASE}/progress`]: [200, { modules: [MATH], students: [] }],
      })
      const page = await show()
      expect(page.find('[data-test=start-level]').exists()).toBe(true)
      expect(page.find('[data-test=no-students]').exists()).toBe(true)
      expect(page.find('table').exists()).toBe(false)
    })

    it('goes back to what counts when the backend says no', async () => {
      backend({
        [`GET ${BASE}`]: [200, GROUP],
        [`GET ${BASE}/progress`]: [200, progress()],
        [`POST ${START}`]: [400, { code: 'invalid_request', message: 'no such level' }],
      })
      const page = await show()
      await page.get('[data-test=start-level] select').setValue('3')
      await flushPromises()
      expect(page.get('[role=alert]').text()).toContain('Die Anfrage war fehlerhaft.')
      expect(/** @type {HTMLSelectElement} */ (page.get('[data-test=start-level] select').element).value).toBe('1')
    })
  })

  it('offers the progress as a file and says what that means', async () => {
    backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/progress`]: [200, progress()],
    })
    const page = await show()
    const link = page.get('[data-test=export]')
    expect(link.text()).toBe('Als CSV herunterladen')
    expect(link.attributes('href')).toBe(`${BASE}/progress/export`)
    expect(page.text()).toContain('der Export wird festgehalten')
  })

  it('offers no file while there is nobody in the list', async () => {
    backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/progress`]: [200, { modules: progress().modules, students: [] }],
    })
    const page = await show()
    expect(page.find('[data-test=export]').exists()).toBe(false)
  })

  it('shows level, workload and trophies per student', async () => {
    backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/progress`]: [200, progress({ locked: true })],
    })
    const page = await show()
    expect(page.get('h1').text()).toBe('Fortschritt der Gruppe 7b')
    expect(page.findAll('th').map((head) => head.text())).toEqual(['Konto', 'Kopfrechnen', 'Trophäen'])

    const rows = page.findAll('[data-test=student]')
    expect(rows).toHaveLength(2)
    expect(rows[0].get('[data-test=cell]').text()).toContain('Niveau 2 von 3')
    expect(rows[0].get('[data-test=cell]').text()).toContain('40 % des Pensums')
    expect(rows[0].get('[data-test=locked]').text()).toBe('Aufstieg gesperrt')
    expect(rows[0].get('[data-test=trophies]').text()).toBe('Rechenpokal (Silber)')
    // Nothing reported yet: the start, said as such.
    expect(rows[1].get('[data-test=cell]').text()).toContain('Niveau 1 von 3')
    expect(rows[1].get('[data-test=cell]').text()).toContain('noch nicht begonnen')
    expect(rows[1].find('[data-test=locked]').exists()).toBe(false)
    // The display name stands below the account, where there is one.
    expect(rows[0].get('[data-test=display-name]').text()).toBe('Lena')
    expect(rows[1].find('[data-test=display-name]').exists()).toBe(false)
    expect(rows[1].text()).toContain('keine')
    expect(page.find('[data-test=detail]').exists()).toBe(false)
    expect(page.find('[data-test=pending-hint]').exists()).toBe(false)
  })

  it('opens a field with the tasks of the level and closes it again', async () => {
    backend({ [`GET ${BASE}`]: [200, GROUP], [`GET ${BASE}/progress`]: [200, progress()] })
    const page = await show()
    const field = page.findAll('[data-test=cell]')[0]
    await field.trigger('click')

    const detail = page.get('[data-test=detail]')
    expect(detail.get('h2').text()).toBe('klugeEule in Kopfrechnen')
    expect(detail.findAll('[data-test=tasks] li').map((task) => task.text())).toEqual([
      'Addieren bis 100: 2 von 5',
      'Subtrahieren bis 100: 0 von 5',
    ])
    // Every level of the module can be chosen, the current one is set.
    expect(detail.findAll('option').map((option) => option.text())).toEqual(['1', '2', '3'])
    expect(/** @type {HTMLSelectElement} */ (detail.get('select').element).value).toBe('2')
    expect(detail.get('[data-test=set-level]').attributes('disabled')).toBeDefined()

    await field.trigger('click')
    expect(page.find('[data-test=detail]').exists()).toBe(false)
  })

  it('orders nothing for the level the student is on', async () => {
    const send = backend({ [`GET ${BASE}`]: [200, GROUP], [`GET ${BASE}/progress`]: [200, progress()] })
    const page = await show()
    await page.findAll('[data-test=cell]')[0].trigger('click')
    // Sent with the enter key, past the button that is switched off.
    await page.get('form').trigger('submit')
    await flushPromises()
    expect(ordered(send)).toEqual([])
    expect(send.mock.calls.every(([, init]) => (init?.method ?? 'GET') === 'GET')).toBe(true)
  })

  it('orders a level from the world and shows that it waits', async () => {
    const send = backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/progress`]: [200, progress()],
      [`POST ${CELL_PATH}`]: [200, progress({ change: 'pending' })],
    })
    const page = await show()
    await page.findAll('[data-test=cell]')[0].trigger('click')
    await page.get('select[name=level]').setValue('3')
    await page.get('form').trigger('submit')
    await flushPromises()

    expect(ordered(send)).toEqual([{ level: 3 }])
    // The page shows what the backend says: still level 2, change on its way.
    const field = page.findAll('[data-test=cell]')[0]
    expect(field.text()).toContain('Niveau 2 von 3')
    expect(field.get('[data-test=change]').text()).toBe('Änderung wartet auf die Welt')
    expect(page.get('[data-test=pending-hint]').text()).toContain('aktualisiert sich von selbst')
  })

  it('locks and unlocks moving up', async () => {
    let locked = false
    const opened = fakeEventSource()
    const send = backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/progress`]: () => [200, progress({ locked })],
      [`POST ${CELL_PATH}`]: () => [200, progress({ locked, change: 'pending' })],
    })
    const page = await show()
    await page.findAll('[data-test=cell]')[0].trigger('click')
    expect(page.get('[data-test=set-locked]').text()).toBe('Aufstieg sperren')
    await page.get('[data-test=set-locked]').trigger('click')
    await flushPromises()
    expect(ordered(send)).toEqual([{ locked: true }])

    // The world has done it and the backend says so: the table loads
    // again by itself, the open field stays open, and the button offers
    // the way back.
    locked = true
    opened[0].change('progress')
    await settled()
    await flushPromises()
    expect(page.get('[data-test=set-locked]').text()).toBe('Aufstieg freigeben')
    await page.get('[data-test=set-locked]').trigger('click')
    await flushPromises()
    expect(ordered(send)).toEqual([{ locked: true }, { locked: false }])
  })

  it('offers to repeat a level whose workload is done', async () => {
    const done = { percent: 100, locked: true }
    const send = backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/progress`]: [200, progress(done)],
      [`POST ${CELL_PATH}`]: [200, progress({ ...done, change: 'pending' })],
    })
    const page = await show()
    // Not for a level that is still being worked on.
    await page.findAll('[data-test=cell]')[1].trigger('click')
    expect(page.find('[data-test=repeat]').exists()).toBe(false)
    expect(page.find('[data-test=repeat-hint]').exists()).toBe(false)

    await page.findAll('[data-test=cell]')[0].trigger('click')
    expect(page.get('[data-test=repeat]').text()).toBe('Niveau wiederholen')
    expect(page.get('[data-test=repeat-hint]').text()).toContain('nur beim ersten Mal')
    await page.get('[data-test=repeat]').trigger('click')
    await flushPromises()
    // The level the student is on, ordered again: the world empties it.
    expect(ordered(send)).toEqual([{ level: 2 }])
    expect(page.get('[data-test=change]').text()).toBe('Änderung wartet auf die Welt')
  })

  it('says when the world refused a change or the backend an order', async () => {
    backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/progress`]: [200, progress({ change: 'refused' })],
      [`POST ${CELL_PATH}`]: [400, { code: 'invalid_request', message: 'the module has no such level' }],
    })
    const page = await show()
    const change = page.get('[data-test=change]')
    expect(change.text()).toBe('Änderung von der Welt abgelehnt')
    expect(change.classes()).toContain('text-red-800')

    await page.findAll('[data-test=cell]')[0].trigger('click')
    await page.get('select[name=level]').setValue('1')
    await page.get('form').trigger('submit')
    await flushPromises()
    expect(page.text()).toContain('Die Anfrage war fehlerhaft.')
    // The table stays as it was.
    expect(page.findAll('[data-test=student]')).toHaveLength(2)
  })

  it('keeps the table when the connection is lost and says so', async () => {
    const opened = fakeEventSource()
    let down = false
    const send = backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/progress`]: () => (down ? [502, { code: 'network', message: 'backend is down' }] : [200, progress()]),
    })
    const page = await show()
    expect(opened.map((source) => source.url)).toEqual([`${BASE}/changes`])
    expect(page.find('[data-test=offline]').exists()).toBe(false)

    down = true
    opened[0].lose()
    await settled()
    expect(page.get('[data-test=offline]').text()).toContain('Verbindung zum Backend ist unterbrochen')
    // A signal that still gets through cannot empty the table.
    opened[0].change('progress')
    await settled()
    await flushPromises()
    expect(page.findAll('[data-test=student]')).toHaveLength(2)

    down = false
    opened[0].open()
    await settled()
    await flushPromises()
    expect(page.find('[data-test=offline]').exists()).toBe(false)
    expect(send.mock.calls.filter(([path]) => path === `${BASE}/progress`).length).toBeGreaterThanOrEqual(3)
  })

  it('explains an empty table', async () => {
    backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/progress`]: [200, { modules: [], students: [] }],
    })
    let page = await show()
    expect(page.get('[data-test=no-modules]').text()).toContain('noch keine Lernmodule')
    expect(page.find('table').exists()).toBe(false)

    backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/progress`]: [200, { modules: [MATH], students: [] }],
    })
    page = await show()
    expect(page.get('[data-test=no-students]').text()).toContain('noch keine Konten')
  })

  it('shows an error if the group cannot be loaded', async () => {
    backend({})
    const page = await show()
    expect(page.text()).toContain('Das gibt es nicht.')
    expect(page.find('table').exists()).toBe(false)
  })
})
