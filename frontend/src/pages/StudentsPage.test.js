import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createMemoryHistory } from 'vue-router'

import { createLepI18n } from '@/i18n'
import { createLepRouter } from '@/router'

import StudentsPage from './StudentsPage.vue'

const GROUP = { id: 'id-7b', name: '7b', teachers: ['lehrer1'], address: 'spiel.schule.example, Port 30000' }
const BASE = '/api/web/v1/groups/id-7b'

/** @param {[string, string][]} pairs account and state */
function students(pairs) {
  return { students: pairs.map(([account, state]) => ({ account, state })) }
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
  const page = mount(StudentsPage, {
    props: { id: 'id-7b' },
    global: { plugins: [router, createLepI18n('de')] },
  })
  await flushPromises()
  return page
}

/** @param {ReturnType<typeof backend>} send */
function calls(send) {
  return send.mock.calls.map(([path, init]) => `${init?.method ?? 'GET'} ${path}`)
}

describe('students page', () => {
  beforeEach(() => setActivePinia(createPinia()))
  afterEach(() => vi.unstubAllGlobals())

  it('shows the accounts of the group with their state', async () => {
    backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/students`]: [200, students([['frohesReh', 'active'], ['klugeEule', 'creating']])],
    })
    const page = await show()
    expect(page.get('h1').text()).toBe('Schülerkonten der Gruppe 7b')
    const rows = page.findAll('[data-test=student]')
    expect(rows.map((row) => row.text())).toEqual(['frohesRehangelegt', 'klugeEulewird in der Welt angelegt'])
    // Nothing to change on accounts that exist or are on their way.
    expect(rows[0].findAll('button')).toHaveLength(0)
    expect(page.find('[data-test=create]').exists()).toBe(false)
    expect(page.text()).toContain('sobald sie verbunden ist')
  })

  it('rolls names and lets single ones be rolled again or removed', async () => {
    const send = backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/students`]: [200, students([])],
      [`POST ${BASE}/students`]: [200, students([['frohesReh', 'draft'], ['klugeEule', 'draft']])],
      [`POST ${BASE}/students/frohesReh/reroll`]: [200, students([['klugeEule', 'draft'], ['mutigerDachs', 'draft']])],
      [`DELETE ${BASE}/students/klugeEule`]: [200, students([['mutigerDachs', 'draft']])],
    })
    const page = await show()
    expect(page.get('[data-test=empty]').text()).toBe('Diese Gruppe hat noch keine Konten.')

    await page.get('input[name=count]').setValue('2')
    await page.get('form').trigger('submit')
    await flushPromises()
    expect(JSON.parse(String(send.mock.calls[2][1]?.body))).toEqual({ count: 2 })
    expect(page.findAll('[data-test=student]')).toHaveLength(2)
    expect(page.get('[data-test=create]').text()).toBe('2 Konten anlegen')

    await page.findAll('[data-test=student]')[0].findAll('button')[0].trigger('click')
    await flushPromises()
    expect(page.findAll('[data-test=student]').map((row) => row.find('td').text())).toEqual(['klugeEule', 'mutigerDachs'])

    await page.findAll('[data-test=student]')[0].findAll('button')[1].trigger('click')
    await flushPromises()
    expect(page.get('[data-test=create]').text()).toBe('Ein Konto anlegen')
    expect(calls(send).slice(2)).toEqual([
      `POST ${BASE}/students`,
      `POST ${BASE}/students/frohesReh/reroll`,
      `DELETE ${BASE}/students/klugeEule`,
    ])
  })

  it('does not ask for a count that makes no sense', async () => {
    const send = backend({ [`GET ${BASE}`]: [200, GROUP], [`GET ${BASE}/students`]: [200, students([])] })
    const page = await show()
    for (const text of ['0', '41', '2.5', '']) {
      await page.get('input[name=count]').setValue(text)
      await page.get('form').trigger('submit')
      await flushPromises()
      expect(page.get('[data-test=invalid]').text(), text).toBe('Bitte eine Zahl von 1 bis 40.')
    }
    expect(send).toHaveBeenCalledTimes(2)
  })

  it('shows the slips once, with names that stay in the browser', async () => {
    let created = false
    const send = backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/students`]: () => [
        200,
        students([['frohesReh', created ? 'creating' : 'draft'], ['klugeEule', created ? 'creating' : 'draft']]),
      ],
      [`POST ${BASE}/students/create`]: () => {
        created = true
        return [200, { slips: [
          { account: 'frohesReh', password: 'berg-see-03' },
          { account: 'klugeEule', password: 'wolke-apfel-47' },
        ] }]
      },
    })
    const print = vi.fn()
    vi.stubGlobal('print', print)
    const page = await show()
    await page.get('[data-test=create]').trigger('click')
    await flushPromises()

    const slips = page.findAll('[data-test=slip]')
    expect(slips).toHaveLength(2)
    expect(slips[1].get('[data-test=account]').text()).toBe('klugeEule')
    expect(slips[1].get('[data-test=password]').text()).toBe('wolke-apfel-47')
    expect(slips[1].get('[data-test=address]').text()).toBe('spiel.schule.example, Port 30000')
    expect(page.text()).toContain('Die Startpasswörter stehen nur jetzt hier.')

    // Every slip has its own field. An empty one is left out of the printout.
    const fields = page.findAll('input[name^=child-]')
    expect(fields).toHaveLength(2)
    expect(slips[0].get('[data-test=child]').text()).toBe('')
    expect(slips[0].get('dt').classes()).toContain('print:hidden')

    // The name of a child goes onto its slip and nowhere else.
    const before = send.mock.calls.length
    await fields[0].setValue(' Anna Muster ')
    expect(slips[0].get('[data-test=child]').text()).toBe('Anna Muster')
    expect(slips[0].get('dt').classes()).not.toContain('print:hidden')
    expect(slips[1].get('[data-test=child]').text()).toBe('')
    expect(slips[1].get('dt').classes()).toContain('print:hidden')
    await page.get('[data-test=print]').trigger('click')
    expect(print).toHaveBeenCalledTimes(1)
    expect(send.mock.calls.length).toBe(before)
    for (const [path, init] of send.mock.calls) {
      expect(`${path} ${String(init?.body ?? '')}`).not.toContain('Anna')
    }

    // After closing, the passwords are gone from the page.
    await page.get('[data-test=done]').trigger('click')
    await flushPromises()
    expect(page.find('[data-test=slip]').exists()).toBe(false)
    expect(page.html()).not.toContain('wolke-apfel-47')
    expect(page.findAll('[data-test=student]')).toHaveLength(2)
  })

  it('says what to do with names the world refused', async () => {
    backend({
      [`GET ${BASE}`]: [200, { ...GROUP, address: undefined }],
      [`GET ${BASE}/students`]: [200, students([['klugeEule', 'refused']])],
    })
    const page = await show()
    expect(page.get('[data-test=refused-hint]').text()).toContain('gibt es in der Welt schon')
    expect(page.get('[data-test=student]').findAll('button')).toHaveLength(2)
    expect(page.find('[data-test=create]').exists()).toBe(false)
  })

  it('shows a failure and keeps the list', async () => {
    backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/students`]: [200, students([['klugeEule', 'draft']])],
      [`POST ${BASE}/students`]: [409, { code: 'no_names', message: 'no free name turned up' }],
    })
    const page = await show()
    await page.get('form').trigger('submit')
    await flushPromises()
    expect(page.get('[role=alert]').text()).toContain('kein freier Name')
    expect(page.findAll('[data-test=student]')).toHaveLength(1)
  })

  it('shows a foreign group as not found', async () => {
    backend({})
    const page = await show()
    expect(page.get('[role=alert]').text()).toContain('Das gibt es nicht.')
    expect(page.find('form').exists()).toBe(false)
  })
})
