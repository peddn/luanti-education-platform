import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createMemoryHistory } from 'vue-router'

import { createLepI18n } from '@/i18n'
import { createLepRouter } from '@/router'
import { fakeEventSource, settled } from '@/test/fakeEventSource'

import RewardsPage from './RewardsPage.vue'

const GROUP = { id: 'id-7b', name: '7b', teachers: ['lehrer1'] }
const BASE = '/api/web/v1/groups/id-7b'

const TABLE = {
  task: { name: 'default:steel_ingot', count: 1 },
  daily: { name: 'default:gold_ingot', count: 1 },
  level: { name: 'default:gold_ingot', count: 1 },
  stage: { name: 'default:diamond', count: 1 },
  module: { name: 'default:diamond', count: 3 },
  daily_limit: 5,
}

const CHOICES = [
  { name: 'default:coal_lump', title: 'Kohleklumpen' },
  { name: 'default:steel_ingot', title: 'Stahlbarren' },
  { name: 'default:gold_ingot', title: 'Goldbarren' },
  { name: 'default:diamond', title: 'Diamant' },
]

/** @param {Record<string, unknown>} [changes] */
function rewards(changes = {}) {
  return { table: TABLE, choices: CHOICES, max_count: 99, max_daily_limit: 20, ...changes }
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
  const page = mount(RewardsPage, {
    props: { id: 'id-7b' },
    global: { plugins: [router, createLepI18n('de')] },
  })
  await flushPromises()
  return page
}

/**
 * @param {ReturnType<typeof backend>} send
 */
function ordered(send) {
  const [, init] = send.mock.calls.filter(([, options]) => options?.method === 'PUT').at(-1) ?? []
  return init?.body ? JSON.parse(String(init.body)) : undefined
}

/**
 * @param {import('@vue/test-utils').VueWrapper} page
 * @param {string} selector
 */
function valueOf(page, selector) {
  return /** @type {HTMLInputElement | HTMLSelectElement} */ (page.get(selector).element).value
}

describe('page of the rewards of a group', () => {
  beforeEach(() => setActivePinia(createPinia()))
  afterEach(() => vi.unstubAllGlobals())

  it('shows the five occasions with what the world pays', async () => {
    backend({ [`GET ${BASE}`]: [200, GROUP], [`GET ${BASE}/rewards`]: [200, rewards()] })
    const page = await show()
    expect(page.get('h1').text()).toBe('Belohnungen: 7b')
    const rows = page.findAll('[data-test=row]')
    expect(rows.map((row) => row.get('td span').text())).toEqual([
      'Aufgabe gelöst',
      'Tagesaufgabe gelöst',
      'Niveau abgeschlossen',
      'Etappe abgeschlossen',
      'Modul abgeschlossen',
    ])
    expect(valueOf(page, 'select[name=item-task]')).toBe('default:steel_ingot')
    expect(valueOf(page, 'input[name=count-module]')).toBe('3')
    expect(valueOf(page, 'input[name=daily-limit]')).toBe('5')
    // Names for people, not the technical ones.
    expect(rows[0].findAll('option').map((option) => option.text())).toEqual([
      'Kohleklumpen',
      'Stahlbarren',
      'Goldbarren',
      'Diamant',
    ])
    expect(page.text()).toContain('das Doppelte')
    expect(page.get('[data-test=save]').attributes('disabled')).toBeDefined()
    expect(page.find('[data-test=discard]').exists()).toBe(false)
  })

  it('orders the whole table once something was changed', async () => {
    const send = backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/rewards`]: [200, rewards()],
      [`PUT ${BASE}/rewards`]: [200, rewards({ change: 'pending' })],
    })
    const page = await show()
    await page.get('select[name=item-task]').setValue('default:coal_lump')
    await page.get('input[name=count-task]').setValue('4')
    await page.get('input[name=daily-limit]').setValue('0')
    expect(page.get('[data-test=save]').attributes('disabled')).toBeUndefined()
    await page.get('form').trigger('submit')
    await flushPromises()

    expect(ordered(send)).toEqual({
      table: { ...TABLE, task: { name: 'default:coal_lump', count: 4 }, daily_limit: 0 },
    })
    // The world has not answered: what counts is shown, and nothing can
    // be changed meanwhile.
    expect(page.get('[data-test=change]').text()).toBe('Änderung wartet auf die Welt')
    expect(valueOf(page, 'select[name=item-task]')).toBe('default:steel_ingot')
    expect(page.get('input[name=count-task]').attributes('disabled')).toBeDefined()
    expect(page.get('[data-test=reset]').attributes('disabled')).toBeDefined()
  })

  it('shows the new table once the world has reported it', async () => {
    const opened = fakeEventSource()
    let answer = rewards({ change: 'pending' })
    backend({ [`GET ${BASE}`]: [200, GROUP], [`GET ${BASE}/rewards`]: () => [200, answer] })
    const page = await show()
    answer = rewards({ table: { ...TABLE, module: { name: 'default:diamond', count: 5 } } })
    opened[0].open()
    opened[0].change('group')
    await settled()
    await flushPromises()
    expect(valueOf(page, 'input[name=count-module]')).toBe('5')
    expect(page.find('[data-test=change]').exists()).toBe(false)
  })

  it('keeps what is being typed when the backend reports something', async () => {
    const opened = fakeEventSource()
    backend({ [`GET ${BASE}`]: [200, GROUP], [`GET ${BASE}/rewards`]: [200, rewards()] })
    const page = await show()
    await page.get('input[name=count-level]').setValue('2')
    opened[0].open()
    opened[0].change('group')
    await settled()
    await flushPromises()
    expect(valueOf(page, 'input[name=count-level]')).toBe('2')

    await page.get('[data-test=discard]').trigger('click')
    expect(valueOf(page, 'input[name=count-level]')).toBe('1')
    expect(page.get('[data-test=save]').attributes('disabled')).toBeDefined()
  })

  it('does not order numbers that cannot be', async () => {
    const send = backend({ [`GET ${BASE}`]: [200, GROUP], [`GET ${BASE}/rewards`]: [200, rewards()] })
    const page = await show()
    for (const [field, value] of [
      ['input[name=count-task]', '0'],
      ['input[name=count-task]', '100'],
      ['input[name=count-task]', '1.5'],
      ['input[name=count-task]', ''],
      ['input[name=daily-limit]', '21'],
      ['input[name=daily-limit]', '-1'],
    ]) {
      const discard = page.find('[data-test=discard]')
      if (discard.exists()) {
        await discard.trigger('click')
      }
      await page.get(field).setValue(value)
      expect(page.get('[data-test=invalid]').text()).toContain('von 1 bis 99')
      expect(page.get('[data-test=save]').attributes('disabled')).toBeDefined()
      await page.get('form').trigger('submit')
    }
    expect(ordered(send)).toBeUndefined()
  })

  it('puts the default back only after asking', async () => {
    const send = backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/rewards`]: [200, rewards()],
      [`PUT ${BASE}/rewards`]: [200, rewards({ change: 'pending' })],
    })
    const page = await show()
    await page.get('[data-test=reset]').trigger('click')
    expect(ordered(send)).toBeUndefined()
    expect(page.text()).toContain('auf die Vorgabe zurückgestellt')
    await page.get('[data-test=reset-yes]').trigger('click')
    await flushPromises()
    expect(ordered(send)).toEqual({})
    expect(page.get('[data-test=change]').text()).toBe('Änderung wartet auf die Welt')
  })

  it('keeps an item the list no longer offers', async () => {
    const table = { ...TABLE, stage: { name: 'default:mese', count: 1 } }
    backend({ [`GET ${BASE}`]: [200, GROUP], [`GET ${BASE}/rewards`]: [200, rewards({ table })] })
    const page = await show()
    expect(valueOf(page, 'select[name=item-stage]')).toBe('default:mese')
    expect(page.get('select[name=item-stage]').findAll('option').at(-1)?.text()).toBe('default:mese')
    expect(page.get('select[name=item-task]').findAll('option')).toHaveLength(4)
  })

  it('says so when the world has reported nothing or refused', async () => {
    backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/rewards`]: [200, { choices: [], max_count: 99, max_daily_limit: 20 }],
    })
    const empty = await show()
    expect(empty.get('[data-test=not-reported]').text()).toContain('noch nicht gemeldet')
    expect(empty.find('form').exists()).toBe(false)

    backend({ [`GET ${BASE}`]: [200, GROUP], [`GET ${BASE}/rewards`]: [200, rewards({ change: 'refused' })] })
    const refused = await show()
    expect(refused.get('[data-test=change]').text()).toContain('abgelehnt')
    expect(refused.get('input[name=count-task]').attributes('disabled')).toBeUndefined()
  })

  it('says so and keeps what was typed when the backend refuses', async () => {
    backend({
      [`GET ${BASE}`]: [200, GROUP],
      [`GET ${BASE}/rewards`]: [200, rewards()],
      [`PUT ${BASE}/rewards`]: [400, { code: 'invalid_request', message: 'no' }],
    })
    const page = await show()
    await page.get('input[name=count-task]').setValue('7')
    await page.get('form').trigger('submit')
    await flushPromises()
    expect(page.get('[role=alert]').text()).toContain('Die Anfrage war fehlerhaft.')
    expect(valueOf(page, 'input[name=count-task]')).toBe('7')
  })
})
