import { describe, expect, it } from 'vitest'

import { FALLBACK, LOCALES, isLocale, pickLocale } from './i18n'
import de from './locales/de.json'
import en from './locales/en.json'
import schema from '../../api/openapi.json'

/**
 * @param {Record<string, unknown>} messages
 * @param {string} [prefix]
 * @returns {string[]}
 */
function keys(messages, prefix = '') {
  return Object.entries(messages).flatMap(([key, value]) =>
    value && typeof value === 'object'
      ? keys(/** @type {Record<string, unknown>} */ (value), `${prefix}${key}.`)
      : [`${prefix}${key}`],
  )
}

describe('languages', () => {
  it('have the same keys', () => {
    expect(keys(en).sort()).toEqual(keys(de).sort())
  })

  it('have no empty text', () => {
    for (const messages of [de, en]) {
      for (const key of keys(messages)) {
        const text = key.split('.').reduce((at, part) => at[part], /** @type {any} */ (messages))
        expect(text, key).toBeTypeOf('string')
        expect(text.trim(), key).not.toBe('')
      }
    }
  })

  it('translate every error code and state of the backend', () => {
    const schemas = schema.components.schemas
    for (const messages of [de, en]) {
      const errors = /** @type {Record<string, string>} */ (messages.errors)
      for (const code of [...schemas.ErrorCode.enum, 'network', 'unexpected']) {
        expect(errors[code], code).toBeTypeOf('string')
      }
      const states = /** @type {Record<string, string>} */ (messages.health.status)
      for (const state of schemas.HealthStatus.enum) {
        expect(states[state], state).toBeTypeOf('string')
      }
      for (const locale of LOCALES) {
        expect(/** @type {Record<string, string>} */ (messages.languages)[locale]).toBeTypeOf('string')
      }
    }
  })
})

describe('pickLocale', () => {
  it('prefers what the user chose', () => {
    expect(pickLocale('en', ['de-DE'])).toBe('en')
  })

  it('takes the first known language of the browser', () => {
    expect(pickLocale(null, ['fr-FR', 'en-GB', 'de'])).toBe('en')
    expect(pickLocale(null, ['de-AT'])).toBe('de')
    expect(pickLocale(null, ['EN'])).toBe('en')
  })

  it('ignores a stored value it does not know', () => {
    expect(pickLocale('xx', ['en'])).toBe('en')
  })

  it('falls back to German', () => {
    expect(pickLocale(null, ['fr', 'es'])).toBe(FALLBACK)
    expect(pickLocale(undefined, [])).toBe('de')
  })

  it('knows its languages', () => {
    expect(isLocale('de')).toBe(true)
    expect(isLocale('fr')).toBe(false)
    expect(isLocale(null)).toBe(false)
  })
})
