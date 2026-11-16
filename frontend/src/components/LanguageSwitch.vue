<script setup>
import { useI18n } from 'vue-i18n'

import { LOCALES, isLocale, rememberLocale } from '@/i18n'

const { locale } = useI18n({ useScope: 'global' })

/** @param {Event} event */
function choose(event) {
  const value = /** @type {HTMLSelectElement} */ (event.target).value
  if (isLocale(value)) {
    locale.value = value
    rememberLocale(value)
  }
}
</script>

<template>
  <label class="flex items-center gap-2 text-sm text-slate-600">
    <span class="sr-only">{{ $t('app.language') }}</span>
    <select
      class="rounded border border-slate-300 bg-white px-2 py-1 text-sm"
      :value="locale"
      @change="choose"
    >
      <option v-for="code in LOCALES" :key="code" :value="code">{{ $t(`languages.${code}`) }}</option>
    </select>
  </label>
</template>
