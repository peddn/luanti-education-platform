import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createMemoryHistory } from 'vue-router'

import { createLepI18n } from '@/i18n'
import { createLepRouter } from '@/router'
import { useAuthStore } from '@/stores/auth'

import GroupPage from './GroupPage.vue'
import GroupsPage from './GroupsPage.vue'

/** @typedef {import('@/api/client').Group} Group */

/** @type {Group} */
const G7B = {
  id: 'id-7b',
  name: '7b',
  teachers: ['lehrer1'],
  last_seen_at: 1700000000,
  world: 'running',
  port: 30000,
}
/** @type {Group} */
const G8A = { id: 'id-8a', name: '8a', teachers: [], world: 'manual' }
/** @type {Group} */
const G9C = { id: 'id-9c', name: '9c', teachers: [], world: 'pending' }
/** @type {Group} */
const REFUSED = { ...G9C, world: 'refused', refusal: 'no port is free: all from 30000 to 30099 are taken' }

/**
 * Logs somebody in for the page and mounts it.
 *
 * @param {object} page
 * @param {boolean} schoolAdmin
 * @param {Record<string, unknown>} [props]
 */
async function show(page, schoolAdmin, props = {}) {
  const auth = useAuthStore()
  auth.me = {
    account: schoolAdmin ? 'leitung' : 'lehrer1',
    email: 'x@schule.example',
    worlds: ['7b'],
    expires_at: 1700043200,
    school_admin: schoolAdmin,
  }
  auth.checked = true
  const router = createLepRouter(createMemoryHistory())
  await router.push('/groups')
  await router.isReady()
  const mounted = mount(page, { props, global: { plugins: [router, createLepI18n('de')] } })
  await flushPromises()
  return mounted
}

/**
 * A backend that answers by method and path.
 *
 * @param {Record<string, [number, unknown]>} answers
 */
function backend(answers) {
  /** @type {(path: string, init?: RequestInit) => Promise<Response>} */
  const answer = async (path, init) => {
    const key = `${init?.method ?? 'GET'} ${path}`
    const [status, body] = answers[key] ?? [404, { code: 'not_found', message: 'no such path' }]
    return new Response(JSON.stringify(body), { status })
  }
  const send = vi.fn(answer)
  vi.stubGlobal('fetch', send)
  return send
}

describe('groups page', () => {
  beforeEach(() => setActivePinia(createPinia()))
  afterEach(() => vi.unstubAllGlobals())

  it('lists the groups with teachers and the state of the world', async () => {
    backend({ 'GET /api/web/v1/groups': [200, { groups: [G7B, G8A] }] })
    const page = await show(GroupsPage, true)
    const rows = page.findAll('[data-test=group]')
    expect(rows).toHaveLength(2)
    expect(rows[0].text()).toContain('7b')
    expect(rows[0].text()).toContain('lehrer1')
    expect(rows[0].text()).toContain('zuletzt verbunden')
    expect(rows[1].text()).toContain('niemand zugeordnet')
    expect(rows[1].text()).toContain('noch nie verbunden')
    expect(rows[0].get('a').attributes('href')).toBe('/groups/id-7b')
    expect(page.text()).toContain('Als Schulverwaltung')
    expect(rows[0].get('[data-test=world-state]').text()).toBe('läuft')
    expect(rows[1].get('[data-test=world-state]').text()).toBe('von Hand eingerichtet')
  })

  it('lets only the school administration create groups', async () => {
    backend({ 'GET /api/web/v1/groups': [200, { groups: [G7B] }] })
    const teacher = await show(GroupsPage, false)
    expect(teacher.find('[data-test=create]').exists()).toBe(false)
    const admin = await show(GroupsPage, true)
    expect(admin.find('[data-test=create]').exists()).toBe(true)
  })

  it('creates a group and shows by itself when its world runs', async () => {
    vi.useFakeTimers()
    try {
      let list = [G7B]
      /** @type {{ method: string, path: string, body: unknown }[]} */
      const sent = []
      /** @type {(path: string, init?: RequestInit) => Promise<Response>} */
      const answer = async (path, init) => {
        const method = init?.method ?? 'GET'
        sent.push({ method, path, body: init?.body ? JSON.parse(String(init.body)) : undefined })
        if (method === 'POST') {
          list = [G7B, G9C]
          return new Response(JSON.stringify(G9C))
        }
        return new Response(JSON.stringify({ groups: list }))
      }
      vi.stubGlobal('fetch', vi.fn(answer))
      const page = await show(GroupsPage, true)

      // An empty name is not sent.
      await page.get('[data-test=create]').trigger('submit')
      expect(page.get('[data-test=invalid]').text()).toContain('1 bis 60 Zeichen')
      expect(sent.filter((call) => call.method === 'POST')).toHaveLength(0)

      await page.get('input[name=new-name]').setValue('  9c ')
      await page.get('[data-test=create]').trigger('submit')
      await flushPromises()
      const posted = sent.filter((call) => call.method === 'POST')
      expect(posted).toEqual([{ method: 'POST', path: '/api/web/v1/groups', body: { name: '9c' } }])
      let rows = page.findAll('[data-test=group]')
      expect(rows).toHaveLength(2)
      expect(rows[1].get('[data-test=world-state]').text()).toBe('wird eingerichtet …')
      expect(/** @type {HTMLInputElement} */ (page.get('input[name=new-name]').element).value).toBe('')

      // The agent reports the world. The page asks again by itself.
      list = [G7B, { ...G9C, world: 'running', port: 30001 }]
      await vi.advanceTimersByTimeAsync(3100)
      await flushPromises()
      rows = page.findAll('[data-test=group]')
      expect(rows[1].get('[data-test=world-state]').text()).toBe('läuft')

      // Nothing is pending any more, so the asking ends.
      const asked = sent.length
      await vi.advanceTimersByTimeAsync(10000)
      expect(sent).toHaveLength(asked)
      page.unmount()
    } finally {
      vi.useRealTimers()
    }
  })

  it('says why a group could not be created', async () => {
    backend({
      'GET /api/web/v1/groups': [200, { groups: [G7B] }],
      'POST /api/web/v1/groups': [409, { code: 'no_game_server', message: 'x' }],
    })
    const page = await show(GroupsPage, true)
    await page.get('input[name=new-name]').setValue('9c')
    await page.get('[data-test=create]').trigger('submit')
    await flushPromises()
    expect(page.get('[data-test=create] [role=alert]').text()).toContain('kein Spielserver eingerichtet')
    expect(page.findAll('[data-test=group]')).toHaveLength(1)
  })

  it('tells a teacher without a group who assigns them', async () => {
    backend({ 'GET /api/web/v1/groups': [200, { groups: [] }] })
    const page = await show(GroupsPage, false)
    expect(page.get('[data-test=empty]').text()).toContain('Das macht die Schulverwaltung.')
  })

  it('offers the school administration to create the first group', async () => {
    backend({ 'GET /api/web/v1/groups': [200, { groups: [] }] })
    const page = await show(GroupsPage, true)
    expect(page.get('[data-test=empty]').text()).toContain('Es gibt noch keine Gruppe.')
    expect(page.find('[data-test=create]').exists()).toBe(true)
  })

  it('shows a failure', async () => {
    backend({ 'GET /api/web/v1/groups': [500, { code: 'internal', message: 'x' }] })
    const page = await show(GroupsPage, false)
    expect(page.get('[role=alert]').text()).toContain('Im Backend ist ein Fehler aufgetreten.')
  })
})

describe('group page', () => {
  beforeEach(() => setActivePinia(createPinia()))
  afterEach(() => vi.unstubAllGlobals())

  it('shows a teacher the group without anything to change', async () => {
    const send = backend({ 'GET /api/web/v1/groups/id-7b': [200, G7B] })
    const page = await show(GroupPage, false, { id: 'id-7b' })
    expect(page.get('[data-test=name]').text()).toBe('7b')
    expect(page.get('[data-test=teachers]').text()).toContain('lehrer1')
    expect(page.find('form').exists()).toBe(false)
    expect(page.text()).toContain('Ändern kann das nur die Schulverwaltung.')
    // The list of all teachers is not asked for.
    expect(send).toHaveBeenCalledTimes(1)
  })

  it('shows state and port of the world', async () => {
    backend({ 'GET /api/web/v1/groups/id-7b': [200, G7B] })
    const page = await show(GroupPage, false, { id: 'id-7b' })
    expect(page.get('[data-test=world-state]').text()).toBe('läuft')
    expect(page.get('[data-test=port]').text()).toContain('Port 30000')
    expect(page.find('[data-test=refused]').exists()).toBe(false)
  })

  it('shows a teacher why the world was refused, without anything to do', async () => {
    backend({ 'GET /api/web/v1/groups/id-9c': [200, REFUSED] })
    const page = await show(GroupPage, false, { id: 'id-9c' })
    expect(page.get('[data-test=world-state]').text()).toBe('abgelehnt')
    expect(page.get('[data-test=refusal]').text()).toBe('no port is free: all from 30000 to 30099 are taken')
    expect(page.find('[data-test=retry]').exists()).toBe(false)
    expect(page.find('[data-test=discard]').exists()).toBe(false)
  })

  it('lets the school administration try a refused group again', async () => {
    const send = backend({
      'GET /api/web/v1/groups/id-9c': [200, REFUSED],
      'GET /api/web/v1/teachers': [200, { teachers: [] }],
      'POST /api/web/v1/groups/id-9c/setup': [200, G9C],
    })
    const page = await show(GroupPage, true, { id: 'id-9c' })
    await page.get('[data-test=retry]').trigger('click')
    await flushPromises()
    const [path, init] = send.mock.calls[2]
    expect(path).toBe('/api/web/v1/groups/id-9c/setup')
    expect(init?.method).toBe('POST')
    expect(page.get('[data-test=world-state]').text()).toBe('wird eingerichtet …')
    expect(page.find('[data-test=refused]').exists()).toBe(false)
  })

  it('lets the school administration discard a refused group', async () => {
    const send = backend({
      'GET /api/web/v1/groups/id-9c': [200, REFUSED],
      'GET /api/web/v1/teachers': [200, { teachers: [] }],
      'DELETE /api/web/v1/groups/id-9c': [200, {}],
      'GET /api/web/v1/groups': [200, { groups: [G7B] }],
    })
    const page = await show(GroupPage, true, { id: 'id-9c' })
    await page.get('[data-test=discard]').trigger('click')
    await flushPromises()
    const [path, init] = send.mock.calls[2]
    expect(path).toBe('/api/web/v1/groups/id-9c')
    expect(init?.method).toBe('DELETE')
    // Back to the list, where the group is gone.
    expect(page.vm.$router.currentRoute.value.name).toBe('groups')
  })

  it('says when a refused group can no longer be handled', async () => {
    backend({
      'GET /api/web/v1/groups/id-9c': [200, REFUSED],
      'GET /api/web/v1/teachers': [200, { teachers: [] }],
      'DELETE /api/web/v1/groups/id-9c': [409, { code: 'wrong_state', message: 'x' }],
    })
    const page = await show(GroupPage, true, { id: 'id-9c' })
    await page.get('[data-test=discard]').trigger('click')
    await flushPromises()
    expect(page.get('[data-test=refused]').text()).toContain('Das geht in diesem Zustand der Gruppe nicht mehr.')
  })

  it('lets a teacher restart and stop a running world, after asking twice', async () => {
    const send = backend({
      'GET /api/web/v1/groups/id-7b': [200, G7B],
      'POST /api/web/v1/groups/id-7b/world': [200, { ...G7B, steering: 'stop' }],
    })
    const page = await show(GroupPage, false, { id: 'id-7b' })
    expect(page.find('[data-test=start]').exists()).toBe(false)
    expect(page.find('[data-test=restart]').exists()).toBe(true)

    // The first click only asks.
    await page.get('[data-test=stop]').trigger('click')
    expect(page.get('[data-test=confirm-stop]').text()).toContain('Wer gerade spielt, wird getrennt.')
    expect(send).toHaveBeenCalledTimes(1)
    await page.get('[data-test=stop-no]').trigger('click')
    expect(page.find('[data-test=confirm-stop]').exists()).toBe(false)
    expect(send).toHaveBeenCalledTimes(1)

    await page.get('[data-test=stop]').trigger('click')
    await page.get('[data-test=stop-yes]').trigger('click')
    await flushPromises()
    const [path, init] = send.mock.calls[1]
    expect(path).toBe('/api/web/v1/groups/id-7b/world')
    expect(JSON.parse(String(init?.body))).toEqual({ step: 'stop' })
    // While the game server works, there is nothing to click.
    expect(page.get('[data-test=steering]').text()).toBe('wird gestoppt …')
    expect(page.find('[data-test=stop]').exists()).toBe(false)
    expect(page.find('[data-test=restart]').exists()).toBe(false)
  })

  it('offers to start a stopped world and says why that failed', async () => {
    const stopped = { ...G7B, world: 'stopped', step_refusal: 'the world was started, but ended at once' }
    const send = backend({
      'GET /api/web/v1/groups/id-7b': [200, stopped],
      'POST /api/web/v1/groups/id-7b/world': [200, { ...G7B, world: 'stopped', steering: 'start' }],
    })
    const page = await show(GroupPage, false, { id: 'id-7b' })
    expect(page.find('[data-test=stop]').exists()).toBe(false)
    expect(page.get('[data-test=step-refusal]').text()).toBe('the world was started, but ended at once')

    await page.get('[data-test=start]').trigger('click')
    await flushPromises()
    expect(JSON.parse(String(send.mock.calls[1][1]?.body))).toEqual({ step: 'start' })
    expect(page.get('[data-test=steering]').text()).toBe('wird gestartet …')
    expect(page.find('[data-test=step-refused]').exists()).toBe(false)
  })

  it('offers nothing to steer for a world the game server does not run', async () => {
    backend({
      'GET /api/web/v1/groups/id-8a': [200, G8A],
      'GET /api/web/v1/groups/id-9c': [200, G9C],
    })
    const manual = await show(GroupPage, false, { id: 'id-8a' })
    expect(manual.find('[data-test=steer]').exists()).toBe(false)
    const pending = await show(GroupPage, false, { id: 'id-9c' })
    expect(pending.find('[data-test=steer]').exists()).toBe(false)
  })

  it('shows an address from the game server without a field to change it', async () => {
    const fixed = { ...G7B, address: 'spiel.schule.example, Port 30000', address_fixed: true }
    const send = backend({
      'GET /api/web/v1/groups/id-7b': [200, fixed],
      'GET /api/web/v1/teachers': [200, { teachers: ['lehrer1'] }],
      'PATCH /api/web/v1/groups/id-7b': [200, fixed],
    })
    const page = await show(GroupPage, true, { id: 'id-7b' })
    expect(page.find('input[name=address]').exists()).toBe(false)
    expect(page.get('[data-test=address]').text()).toBe('spiel.schule.example, Port 30000')
    await page.get('form').trigger('submit')
    await flushPromises()
    expect(JSON.parse(String(send.mock.calls[2][1]?.body))).toEqual({ teachers: ['lehrer1'] })
  })

  it('lets the school administration rename and assign', async () => {
    const changed = { ...G7B, name: 'Klasse 7b', teachers: ['lehrer2', 'leitung'] }
    const send = backend({
      'GET /api/web/v1/groups/id-7b': [200, G7B],
      'GET /api/web/v1/teachers': [200, { teachers: ['lehrer2', 'leitung'] }],
      'PATCH /api/web/v1/groups/id-7b': [200, changed],
    })
    const page = await show(GroupPage, true, { id: 'id-7b' })

    // lehrer1 is assigned and stays offered, although no longer a teacher.
    const boxes = page.findAll('input[type=checkbox]')
    expect(boxes.map((box) => box.attributes('value'))).toEqual(['lehrer1', 'lehrer2', 'leitung'])
    expect(boxes.map((box) => /** @type {HTMLInputElement} */ (box.element).checked)).toEqual([true, false, false])

    await page.get('input[name=name]').setValue('  Klasse 7b ')
    await boxes[0].setValue(false)
    await boxes[2].setValue(true)
    await boxes[1].setValue(true)
    await page.get('form').trigger('submit')
    await flushPromises()

    const [path, init] = send.mock.calls[2]
    expect(path).toBe('/api/web/v1/groups/id-7b')
    expect(init?.method).toBe('PATCH')
    expect(JSON.parse(String(init?.body))).toEqual({ name: 'Klasse 7b', teachers: ['lehrer2', 'leitung'] })
    expect(page.get('[data-test=name]').text()).toBe('Klasse 7b')
    expect(page.get('[data-test=saved]').text()).toBe('Gespeichert.')
  })

  it('sends the address of the world when it changed', async () => {
    const send = backend({
      'GET /api/web/v1/groups/id-7b': [200, { ...G7B, address: 'alt.schule.example' }],
      'GET /api/web/v1/teachers': [200, { teachers: ['lehrer1'] }],
      'PATCH /api/web/v1/groups/id-7b': [200, { ...G7B, address: 'spiel.schule.example, Port 30000' }],
    })
    const page = await show(GroupPage, true, { id: 'id-7b' })
    const field = page.get('input[name=address]')
    expect(/** @type {HTMLInputElement} */ (field.element).value).toBe('alt.schule.example')
    await field.setValue(' spiel.schule.example, Port 30000 ')
    await page.get('form').trigger('submit')
    await flushPromises()
    expect(JSON.parse(String(send.mock.calls[2][1]?.body))).toEqual({
      teachers: ['lehrer1'],
      address: 'spiel.schule.example, Port 30000',
    })
    expect(page.get('[data-test=students]').attributes('href')).toBe('/groups/id-7b/students')
  })

  it('shows a teacher the address without a field', async () => {
    backend({ 'GET /api/web/v1/groups/id-7b': [200, { ...G7B, address: 'spiel.schule.example' }] })
    const page = await show(GroupPage, false, { id: 'id-7b' })
    expect(page.get('[data-test=address]').text()).toBe('spiel.schule.example')
    expect(page.find('input[name=address]').exists()).toBe(false)
  })

  it('sends no name that did not change', async () => {
    const send = backend({
      'GET /api/web/v1/groups/id-7b': [200, G7B],
      'GET /api/web/v1/teachers': [200, { teachers: ['lehrer1'] }],
      'PATCH /api/web/v1/groups/id-7b': [200, G7B],
    })
    const page = await show(GroupPage, true, { id: 'id-7b' })
    await page.get('form').trigger('submit')
    await flushPromises()
    expect(JSON.parse(String(send.mock.calls[2][1]?.body))).toEqual({ teachers: ['lehrer1'] })
  })

  it('does not send a name that cannot be one', async () => {
    const send = backend({
      'GET /api/web/v1/groups/id-7b': [200, G7B],
      'GET /api/web/v1/teachers': [200, { teachers: [] }],
    })
    const page = await show(GroupPage, true, { id: 'id-7b' })
    await page.get('input[name=name]').setValue('   ')
    await page.get('form').trigger('submit')
    await flushPromises()
    expect(page.get('[data-test=invalid]').text()).toBe('Der Name braucht 1 bis 60 Zeichen.')
    expect(send).toHaveBeenCalledTimes(2)
  })

  it('says when another group has the name and keeps what was typed', async () => {
    backend({
      'GET /api/web/v1/groups/id-7b': [200, G7B],
      'GET /api/web/v1/teachers': [200, { teachers: [] }],
      'PATCH /api/web/v1/groups/id-7b': [409, { code: 'name_taken', message: 'another group has this name' }],
    })
    const page = await show(GroupPage, true, { id: 'id-7b' })
    await page.get('input[name=name]').setValue('8a')
    await page.get('form').trigger('submit')
    await flushPromises()
    expect(page.get('[role=alert]').text()).toContain('Eine andere Gruppe heißt schon so.')
    expect(/** @type {HTMLInputElement} */ (page.get('input[name=name]').element).value).toBe('8a')
    expect(page.get('[data-test=name]').text()).toBe('7b')
    expect(page.find('[data-test=saved]').exists()).toBe(false)
  })

  it('shows a group that does not exist for the teacher as not found', async () => {
    backend({})
    const page = await show(GroupPage, false, { id: 'id-8a' })
    expect(page.get('[role=alert]').text()).toContain('Das gibt es nicht.')
    expect(page.find('[data-test=name]').exists()).toBe(false)
  })
})
