import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createMemoryHistory } from 'vue-router'

import { createLepI18n } from '@/i18n'
import { createLepRouter } from '@/router'

import LoginPage from './LoginPage.vue'

const ANNA = { account: 'lehrer1', email: 'anna@schule.example', worlds: ['7b'], expires_at: 1700043200 }

/**
 * @param {string} address
 * @param {import('@/i18n').Locale} [locale]
 */
async function show(address, locale = 'de') {
  const router = createLepRouter(createMemoryHistory())
  await router.push(address)
  await router.isReady()
  const page = mount(LoginPage, { global: { plugins: [router, createLepI18n(locale)] } })
  return { page, router }
}

/**
 * A backend that answers by path.
 *
 * @param {Record<string, [number, unknown]>} answers
 */
function backend(answers) {
  /** @type {(path: string, init?: RequestInit) => Promise<Response>} */
  const answer = async (path) => {
    const [status, body] = answers[path] ?? [404, { code: 'not_found', message: 'no such path' }]
    return new Response(JSON.stringify(body), { status })
  }
  const send = vi.fn(answer)
  vi.stubGlobal('fetch', send)
  return send
}

describe('login page', () => {
  beforeEach(() => setActivePinia(createPinia()))
  afterEach(() => vi.unstubAllGlobals())

  it('asks for a link and answers the same for every address', async () => {
    const send = backend({ '/api/web/v1/login/link': [200, {}] })
    const { page } = await show('/login')
    await page.get('input').setValue('  Anna@Schule.Example ')
    await page.get('form').trigger('submit')
    await flushPromises()

    expect(send).toHaveBeenCalledTimes(1)
    const [path, init] = send.mock.calls[0]
    expect(path).toBe('/api/web/v1/login/link')
    expect(JSON.parse(String(init?.body))).toEqual({ email: 'Anna@Schule.Example' })
    expect(page.get('[data-test=sent]').text()).toContain('Wenn diese Adresse zu einem Web-Zugang gehört')
  })

  it('does not send what is no address', async () => {
    const send = backend({})
    const { page } = await show('/login')
    for (const text of ['', 'anna', 'anna@schule', 'an na@schule.example']) {
      await page.get('input').setValue(text)
      await page.get('form').trigger('submit')
      await flushPromises()
      expect(page.get('[data-test=invalid]').text(), text).toBe('Das ist keine E-Mail-Adresse.')
    }
    expect(send).not.toHaveBeenCalled()
    expect(page.find('[data-test=sent]').exists()).toBe(false)
  })

  it('says when the backend is out of reach', async () => {
    vi.stubGlobal('fetch', async () => {
      throw new TypeError('fetch failed')
    })
    const { page } = await show('/login', 'en')
    await page.get('input').setValue('anna@schule.example')
    await page.get('form').trigger('submit')
    await flushPromises()
    expect(page.get('[role=alert]').text()).toContain('The backend cannot be reached.')
    expect(page.find('[data-test=sent]').exists()).toBe(false)
  })

  it('does nothing with a token until the button is pressed', async () => {
    const send = backend({ '/api/web/v1/login': [200, ANNA] })
    const { page } = await show('/login?token=lepl_abc')
    await flushPromises()
    expect(send).not.toHaveBeenCalled()
    expect(page.find('input').exists()).toBe(false)
    expect(page.get('[data-test=log-in]').text()).toBe('Anmelden')
  })

  it('logs in with the token and goes to the overview', async () => {
    const send = backend({ '/api/web/v1/login': [200, ANNA], '/api/web/v1/me': [200, ANNA] })
    const { page, router } = await show('/login?token=lepl_abc')
    await page.get('[data-test=log-in]').trigger('click')
    await flushPromises()

    const [path, init] = send.mock.calls[0]
    expect(path).toBe('/api/web/v1/login')
    expect(JSON.parse(String(init?.body))).toEqual({ token: 'lepl_abc' })
    expect(router.currentRoute.value.name).toBe('overview')
    // The token is gone from the address.
    expect(router.currentRoute.value.query.token).toBeUndefined()
  })

  it('offers a new link when the old one no longer works', async () => {
    backend({
      '/api/web/v1/login': [400, { code: 'invalid_token', message: 'the token is unknown, used or too old' }],
    })
    const { page, router } = await show('/login?token=lepl_old')
    await page.get('[data-test=log-in]').trigger('click')
    await flushPromises()
    expect(page.get('[role=alert]').text()).toContain('Dieser Link gilt nicht mehr.')
    expect(page.find('[data-test=log-in]').exists()).toBe(false)
    expect(page.get('[data-test=new-link]').text()).toBe('Neuen Link anfordern')
    expect(router.currentRoute.value.name).toBe('login')
  })
})
