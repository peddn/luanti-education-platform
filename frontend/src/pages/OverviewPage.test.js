import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'

import { createLepI18n } from '@/i18n'
import { useAuthStore } from '@/stores/auth'

import OverviewPage from './OverviewPage.vue'

describe('overview page', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('shows who is logged in', () => {
    const auth = useAuthStore()
    auth.me = { account: 'lehrer1', email: 'anna@schule.example', worlds: ['7b', '8a'], expires_at: 1700043200, school_admin: false }
    const page = mount(OverviewPage, { global: { plugins: [createLepI18n('de')] } })
    expect(page.text()).toContain('Du bist als lehrer1 angemeldet.')
    expect(page.get('[data-test=email]').text()).toBe('anna@schule.example')
    expect(page.get('[data-test=worlds]').text()).toBe('7b, 8a')
    expect(page.get('[data-test=until]').text()).toContain('2023')
  })

  it('shows nothing without a teacher', () => {
    const page = mount(OverviewPage, { global: { plugins: [createLepI18n('en')] } })
    expect(page.text()).toBe('')
  })
})
