// Languages of the frontend. No text stands in a page, everything comes
// from the files in locales/.

import { createI18n } from 'vue-i18n'

import de from './locales/de.json'
import en from './locales/en.json'

/** @typedef {'de' | 'en'} Locale */

/** @type {readonly Locale[]} */
export const LOCALES = ['de', 'en']

/** @type {Locale} */
export const FALLBACK = 'de'

const STORAGE_KEY = 'lep.locale'

/**
 * @param {unknown} value
 * @returns {value is Locale}
 */
export function isLocale(value) {
  return LOCALES.includes(/** @type {Locale} */ (value))
}

/**
 * Picks the language: the one the user chose before, else the first
 * language of the browser the frontend knows, else German.
 *
 * @param {string | null | undefined} stored
 * @param {readonly string[]} wanted languages of the browser, best first
 * @returns {Locale}
 */
export function pickLocale(stored, wanted) {
  if (isLocale(stored)) {
    return stored
  }
  for (const language of wanted) {
    const short = language.toLowerCase().split('-')[0]
    if (isLocale(short)) {
      return short
    }
  }
  return FALLBACK
}

/** @returns {string | null} */
function readStored() {
  try {
    return window.localStorage.getItem(STORAGE_KEY)
  } catch {
    return null
  }
}

/**
 * @param {Locale} [locale]
 */
export function createLepI18n(locale) {
  const start = locale ?? pickLocale(readStored(), navigator.languages ?? [])
  document.documentElement.lang = start
  return createI18n({
    legacy: false,
    locale: start,
    fallbackLocale: FALLBACK,
    messages: { de, en },
  })
}

/**
 * Remembers the chosen language in this browser and tells the page.
 *
 * @param {Locale} locale
 */
export function rememberLocale(locale) {
  document.documentElement.lang = locale
  try {
    window.localStorage.setItem(STORAGE_KEY, locale)
  } catch {
    // Without storage the choice lasts until the page is closed.
  }
}
