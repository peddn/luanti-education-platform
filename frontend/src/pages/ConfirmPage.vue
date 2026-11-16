<script setup>
import { computed, ref } from 'vue'
import { useRoute } from 'vue-router'

import { api, errorCode } from '@/api/client'
import ErrorNote from '@/components/ErrorNote.vue'

/** @typedef {import('@/api/client').ErrorCode} ErrorCode */

const route = useRoute()

// The token from the mail. Opening the page does nothing with it: only
// the button confirms, so a mail program that looks at the link in
// advance does not use it up.
const token = computed(() => {
  const value = route.query.token
  return typeof value === 'string' ? value.trim() : ''
})

const working = ref(false)
const account = ref(/** @type {string | null} */ (null))
const error = ref(/** @type {ErrorCode | null} */ (null))

async function confirm() {
  working.value = true
  error.value = null
  try {
    account.value = (await api.confirm(token.value)).account
  } catch (err) {
    error.value = errorCode(err)
  } finally {
    working.value = false
  }
}
</script>

<template>
  <section class="max-w-xl space-y-6">
    <h1 class="text-2xl font-bold">{{ $t('confirm.title') }}</h1>

    <div
      v-if="account"
      data-test="done"
      role="status"
      class="rounded border border-emerald-200 bg-emerald-50 px-4 py-3 text-emerald-900"
    >
      <p class="font-semibold">{{ $t('confirm.done') }}</p>
      <p class="text-sm">{{ $t('confirm.doneAccount', { account }) }}</p>
    </div>

    <template v-else-if="token">
      <p class="text-slate-600">{{ $t('confirm.intro') }}</p>
      <template v-if="error">
        <ErrorNote :code="error" />
        <p v-if="error === 'invalid_token'" class="text-sm text-slate-600">{{ $t('confirm.again') }}</p>
      </template>
      <button
        v-if="error !== 'invalid_token' && error !== 'address_taken'"
        type="button"
        class="rounded bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800 disabled:opacity-50"
        :disabled="working"
        @click="confirm"
      >
        {{ working ? $t('confirm.working') : $t('confirm.button') }}
      </button>
    </template>

    <div v-else data-test="missing" class="space-y-2 text-slate-600">
      <p>{{ $t('confirm.missing') }}</p>
      <p class="text-sm">{{ $t('confirm.again') }}</p>
    </div>
  </section>
</template>
