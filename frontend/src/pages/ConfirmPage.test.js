import { flushPromises, mount } from '@vue/test-utils'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { createMemoryHistory } from 'vue-router'

import { createLepI18n } from '@/i18n'
import { createLepRouter } from '@/router'

import ConfirmPage from './ConfirmPage.vue'

/**
 * @param {string} address
 * @param {import('@/i18n').Locale} [locale]
 */
async function show(address, locale = 'de') {
  const router = createLepRouter(createMemoryHistory())
  await router.push(address)
  await router.isReady()
  return mount(ConfirmPage, { global: { plugins: [router, createLepI18n(locale)] } })
}

/**
 * @param {number} status
 * @param {unknown} body
 */
function backend(status, body) {
  /** @type {(path: string, init: RequestInit) => Promise<Response>} */
  const answer = async () => new Response(JSON.stringify(body), { status })
  const send = vi.fn(answer)
  vi.stubGlobal('fetch', send)
  return send
}

describe('confirm page', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('does nothing until the button is pressed', async () => {
    const send = backend(200, { account: 'lehrer1' })
    const page = await show('/confirm?token=lepc_abc')
    await flushPromises()
    expect(send).not.toHaveBeenCalled()
    expect(page.get('button').text()).toBe('Adresse bestätigen')
  })

  it('confirms with the token from the address', async () => {
    const send = backend(200, { account: 'lehrer1' })
    const page = await show('/confirm?token=lepc_abc')
    await page.get('button').trigger('click')
    await flushPromises()

    expect(send).toHaveBeenCalledTimes(1)
    const [path, init] = send.mock.calls[0]
    expect(path).toBe('/api/web/v1/confirm')
    expect(init.method).toBe('POST')
    expect(JSON.parse(String(init.body))).toEqual({ token: 'lepc_abc' })

    const done = page.get('[data-test=done]').text()
    expect(done).toContain('Die Adresse ist bestätigt.')
    expect(done).toContain('lehrer1')
    expect(page.find('button').exists()).toBe(false)
  })

  it('says when the link no longer works, without a button to try again', async () => {
    backend(400, { code: 'invalid_token', message: 'the token is unknown, used or too old' })
    const page = await show('/confirm?token=lepc_old', 'en')
    await page.get('button').trigger('click')
    await flushPromises()
    expect(page.get('[role=alert]').text()).toContain('This link no longer works.')
    expect(page.text()).toContain('ask for a new mail')
    expect(page.find('button').exists()).toBe(false)
    expect(page.find('[data-test=done]').exists()).toBe(false)
  })

  it('says when the address belongs to another account', async () => {
    backend(409, { code: 'address_taken', message: 'the address belongs to another account' })
    const page = await show('/confirm?token=lepc_abc')
    await page.get('button').trigger('click')
    await flushPromises()
    expect(page.get('[role=alert]').text()).toContain('gehört schon zu einem anderen Konto')
    expect(page.find('button').exists()).toBe(false)
  })

  it('lets the teacher try again when the backend is out of reach', async () => {
    vi.stubGlobal('fetch', async () => {
      throw new TypeError('fetch failed')
    })
    const page = await show('/confirm?token=lepc_abc')
    await page.get('button').trigger('click')
    await flushPromises()
    expect(page.get('[role=alert]').text()).toContain('nicht erreichbar')
    expect(page.get('button').text()).toBe('Adresse bestätigen')
  })

  it('explains an address without a token', async () => {
    const send = backend(200, {})
    const page = await show('/confirm')
    expect(page.find('button').exists()).toBe(false)
    expect(page.get('[data-test=missing]').text()).toContain('fehlt der Teil aus der Mail')
    expect(send).not.toHaveBeenCalled()
  })
})
