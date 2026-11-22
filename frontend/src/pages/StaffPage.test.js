import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createLepI18n } from '@/i18n'
import { useAuthStore } from '@/stores/auth'

import StaffPage from './StaffPage.vue'

const PATH = '/api/web/v1/staff'

/** @param {Record<string, unknown>[]} list */
function staff(list) {
  return {
    staff: list.map((entry) => ({
      holder: true,
      school_admin: false,
      web_access: 'none',
      groups: [],
      worlds: [],
      ...entry,
    })),
  }
}

const LIST = staff([
  { account: 'frau_meier', state: 'active', web_access: 'confirmed', groups: ['7b', '8a'] },
  { account: 'herr_k', state: 'creating', holder: false },
  { account: 'lehrer1', web_access: 'pending' },
  { account: 'leitung', school_admin: true, web_access: 'confirmed' },
  { account: 'zweite_leitung', school_admin: true },
])

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
  useAuthStore().me = {
    account: 'leitung',
    email: 'leitung@schule.example',
    worlds: ['7b'],
    expires_at: 1700043200,
    school_admin: true,
  }
  const page = mount(StaffPage, { global: { plugins: [createLepI18n('de')] } })
  await flushPromises()
  return page
}

/** @param {ReturnType<typeof backend>} send */
function calls(send) {
  return send.mock.calls.map(([path, init]) => `${init?.method ?? 'GET'} ${path}`)
}

/**
 * @param {ReturnType<typeof backend>} send
 * @param {string} path
 */
function sent(send, path) {
  const [, init] = send.mock.calls.find(([called, options]) => called === path && options?.method === 'POST') ?? []
  return init?.body ? JSON.parse(String(init.body)) : undefined
}

describe('page of the teachers', () => {
  beforeEach(() => setActivePinia(createPinia()))
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.useRealTimers()
  })

  it('lists the teachers with state, web access and groups', async () => {
    backend({ [`GET ${PATH}`]: [200, LIST] })
    const page = await show()
    expect(page.get('h1').text()).toBe('Lehrkräfte')
    const rows = page.findAll('[data-test=teacher]').map((row) => row.findAll('td').map((cell) => cell.text()))
    expect(rows[0].slice(0, 4)).toEqual(['frau_meier', 'angelegt', 'eingerichtet', '7b, 8a'])
    expect(rows[1].slice(0, 4)).toEqual(['herr_k', 'wird in den Welten angelegt', 'nicht eingerichtet', 'keine'])
    expect(rows[2].slice(0, 3)).toEqual(['lehrer1', 'im Spiel angelegt', 'Adresse wartet auf Bestätigung'])
    expect(rows[3][1]).toBe('Schulverwaltung')
  })

  it('offers nothing for the school administration and the own account', async () => {
    backend({ [`GET ${PATH}`]: [200, LIST] })
    const page = await show()
    const rows = page.findAll('[data-test=teacher]')
    expect(rows[0].findAll('button').map((button) => button.text())).toEqual(['Passwort zurücksetzen', 'Konto löschen'])
    // Not created yet: nothing to reset, but it can be taken back.
    expect(rows[1].findAll('button').map((button) => button.text())).toEqual(['Konto löschen'])
    expect(rows[3].findAll('button')).toHaveLength(0)
    expect(rows[3].get('[data-test=protected]').text()).toBe('wird nur im Spiel vom Admin verwaltet')
    expect(rows[4].findAll('button')).toHaveLength(0)
  })

  it('creates a teacher with a chosen name and shows the slip once', async () => {
    const send = backend({
      [`GET ${PATH}`]: [200, LIST],
      [`POST ${PATH}`]: [200, { slips: [{ account: 'frau_schulz', password: 'wolke-apfel-47-birne-mond-12' }] }],
    })
    const page = await show()

    for (const bad of ['x', 'frau schulz', 'müller', '']) {
      await page.get('input[name=name]').setValue(bad)
      await page.get('[data-test=create]').trigger('submit')
      expect(page.get('[data-test=invalid]').text()).toContain('2 bis 19 Zeichen')
    }
    expect(calls(send)).toEqual([`GET ${PATH}`])

    await page.get('input[name=name]').setValue(' frau_schulz ')
    await page.get('[data-test=create]').trigger('submit')
    await flushPromises()
    expect(sent(send, PATH)).toEqual({ name: 'frau_schulz' })

    expect(page.get('[data-test=account]').text()).toBe('frau_schulz')
    expect(page.get('[data-test=password]').text()).toBe('wolke-apfel-47-birne-mond-12')
    // A slip for a teacher asks nothing about a child.
    expect(page.find('input[name=child-0]').exists()).toBe(false)
    expect(page.get('[data-test=staff-note]').text()).toContain('persönlich')
    expect(page.find('[data-test=reset-note]').exists()).toBe(false)

    await page.get('[data-test=done]').trigger('click')
    await flushPromises()
    expect(page.find('[data-test=password]').exists()).toBe(false)
    expect(page.get('h1').text()).toBe('Lehrkräfte')
    expect(/** @type {HTMLInputElement} */ (page.get('input[name=name]').element).value).toBe('')
  })

  it('says so when the name is taken', async () => {
    backend({
      [`GET ${PATH}`]: [200, LIST],
      [`POST ${PATH}`]: [409, { code: 'account_taken', message: 'taken' }],
    })
    const page = await show()
    await page.get('input[name=name]').setValue('lehrer1')
    await page.get('[data-test=create]').trigger('submit')
    await flushPromises()
    expect(page.get('[role=alert]').text()).toContain('schon vergeben oder wurde gelöscht')
    expect(/** @type {HTMLInputElement} */ (page.get('input[name=name]').element).value).toBe('lehrer1')
  })

  it('resets a password only after asking', async () => {
    const send = backend({
      [`GET ${PATH}`]: [200, LIST],
      [`POST ${PATH}/frau_meier/password`]: [200, { slips: [{ account: 'frau_meier', password: 'a-b-1-c-d-2' }] }],
    })
    const page = await show()
    await page.get('[data-test=reset]').trigger('click')
    expect(calls(send)).toEqual([`GET ${PATH}`])
    expect(page.text()).toContain('Das alte Passwort gilt dann nicht mehr.')
    await page.get('[data-test=reset-yes]').trigger('click')
    await flushPromises()
    expect(page.get('[data-test=password]').text()).toBe('a-b-1-c-d-2')
    expect(page.get('[data-test=reset-note]').text()).toContain('sobald die Welten es übernommen haben')
  })

  it('deletes a teacher after the name was typed', async () => {
    const send = backend({
      [`GET ${PATH}`]: [200, LIST],
      [`POST ${PATH}/frau_meier/removal`]: [
        200,
        staff([{ account: 'frau_meier', state: 'active', removal: 'pending' }, { account: 'leitung', school_admin: true }]),
      ],
    })
    const page = await show()
    await page.get('[data-test=removal]').trigger('click')
    const form = page.get('[data-test=removal-form]')
    expect(form.get('h2').text()).toBe('Konto frau_meier endgültig löschen')
    expect(form.text()).toContain('in jeder Welt gelöscht')
    expect(form.get('[data-test=removal-yes]').attributes('disabled')).toBeDefined()

    await form.get('input[name=confirm]').setValue('Frau_Meier')
    await form.get('form').trigger('submit')
    await flushPromises()
    expect(calls(send)).toEqual([`GET ${PATH}`])

    await form.get('input[name=confirm]').setValue('frau_meier')
    await form.get('form').trigger('submit')
    await flushPromises()
    expect(sent(send, `${PATH}/frau_meier/removal`)).toEqual({ confirm: 'frau_meier' })
    expect(page.find('[data-test=removal-form]').exists()).toBe(false)
    const row = page.findAll('[data-test=teacher]')[0]
    expect(row.get('[data-test=removal-state]').text()).toBe('Löschung wartet auf die Welt')
    expect(row.find('[data-test=removal]').exists()).toBe(false)
  })

  it('shows why the worlds refused', async () => {
    backend({
      [`GET ${PATH}`]: [
        200,
        staff([
          { account: 'frau_meier', state: 'active', removal: 'refused', removal_refusal: 'staff', password: 'refused' },
          { account: 'herr_k', state: 'refused', holder: false },
        ]),
      ],
    })
    const page = await show()
    const rows = page.findAll('[data-test=teacher]')
    expect(rows[0].get('[data-test=removal-state]').text()).toContain('Löschung abgelehnt')
    expect(rows[0].get('[data-test=password-state]').text()).toContain('abgelehnt')
    expect(rows[1].get('[data-test=state]').text()).toContain('Den Namen gibt es dort schon')
    // A name the worlds refused can only be taken off the list.
    expect(rows[1].findAll('button').map((button) => button.text())).toEqual(['Konto löschen'])
  })

  it('tells in which worlds a teacher has arrived', async () => {
    backend({
      [`GET ${PATH}`]: [
        200,
        staff([
          {
            account: 'frau_meier',
            state: 'active',
            worlds: [
              { group: '7b', state: 'arrived' },
              { group: '8a', state: 'password_waiting' },
              { group: '9c', state: 'waiting' },
              { group: '9d', state: 'refused' },
              { group: '9e', state: 'missing' },
            ],
          },
          { account: 'herr_k', state: 'active', worlds: [{ group: '7b', state: 'arrived' }] },
          { account: 'lehrer1' },
        ]),
      ],
    })
    const page = await show()
    const rows = page.findAll('[data-test="teacher"]')

    // The account is there in two worlds, in one of them with the
    // password from before.
    const worlds = rows[0].get('[data-test="worlds"]')
    expect(worlds.get('summary').text()).toBe('Gruppen: 2 von 5 angelegt')
    expect(worlds.get('summary').classes()).toContain('text-amber-700')
    expect(
      worlds.findAll('[data-test="world"]').map((world) => world.findAll('span').map((part) => part.text())),
    ).toEqual([
      ['7b', 'angelegt'],
      ['8a', 'angelegt, das neue Passwort wartet auf die Welt'],
      ['9c', 'wartet, bis die Welt den Auftrag abholt'],
      ['9d', 'von der Welt abgelehnt'],
      ['9e', 'nicht angelegt'],
    ])

    const everywhere = rows[1].get('[data-test="worlds"] summary')
    expect(everywhere.text()).toBe('Gruppen: 1 von 1 angelegt')
    expect(everywhere.classes()).not.toContain('text-amber-700')

    // Nothing is known about an account from the game.
    expect(rows[2].find('[data-test="worlds"]').exists()).toBe(false)
  })

  it('asks again while a world has not answered', async () => {
    vi.useFakeTimers()
    let list = LIST
    const send = backend({ [`GET ${PATH}`]: () => [200, list] })
    const page = await show()
    expect(page.findAll('[data-test=teacher]')[1].text()).toContain('wird in den Welten angelegt')

    list = staff([{ account: 'herr_k', state: 'active' }])
    await vi.advanceTimersByTimeAsync(3000)
    await flushPromises()
    expect(page.findAll('[data-test=teacher]').map((row) => row.get('[data-test=state]').text())).toEqual(['angelegt'])
    // Nothing waits any more: the page is quiet.
    const before = send.mock.calls.length
    await vi.advanceTimersByTimeAsync(9000)
    expect(send.mock.calls.length).toBe(before)
  })

  it('shows the refusal to who is not the school administration', async () => {
    backend({ [`GET ${PATH}`]: [403, { code: 'forbidden', message: 'no' }] })
    const page = await show()
    expect(page.get('[role=alert]').text()).toContain('Das darfst du nicht.')
    expect(page.find('h1').exists()).toBe(false)
  })
})
