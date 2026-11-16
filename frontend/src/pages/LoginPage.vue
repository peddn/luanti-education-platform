<script setup>
import { computed, ref, watchEffect } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'

import { api, errorCode } from '@/api/client'
import ErrorNote from '@/components/ErrorNote.vue'
import { useAuthStore } from '@/stores/auth'

/** @typedef {import('@/api/client').ErrorCode} ErrorCode */

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()

// The token from the mail. Opening the page does nothing with it: only
// the button logs in, so a mail program that looks at the link in
// advance does not use it up.
const token = computed(() => {
  const value = route.query.token
  return typeof value === 'string' ? value.trim() : ''
})

const email = ref('')
const working = ref(false)
const sent = ref(false)
const invalidEmail = ref(false)
const error = ref(/** @type {ErrorCode | null} */ (null))

// Who is logged in has nothing to do here.
watchEffect(() => {
  if (auth.loggedIn) {
    router.replace({ name: 'overview' })
  }
})

async function askForLink() {
  error.value = null
  sent.value = false
  const address = email.value.trim()
  invalidEmail.value = !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address)
  if (invalidEmail.value) {
    return
  }
  working.value = true
  try {
    await api.requestLoginLink(address)
    sent.value = true
  } catch (err) {
    error.value = errorCode(err)
  } finally {
    working.value = false
  }
}

async function logIn() {
  working.value = true
  error.value = null
  try {
    await auth.login(token.value)
  } catch (err) {
    error.value = errorCode(err)
  } finally {
    working.value = false
  }
}
</script>

<template>
  <section class="max-w-xl space-y-6">
    <h1 class="text-2xl font-bold">{{ $t('login.title') }}</h1>

    <template v-if="token">
      <p class="text-slate-600">{{ $t('login.linkIntro') }}</p>
      <ErrorNote v-if="error" :code="error" />
      <RouterLink
        v-if="error === 'invalid_token'"
        :to="{ name: 'login' }"
        data-test="new-link"
        class="inline-block text-emerald-700 underline"
      >
        {{ $t('login.newLink') }}
      </RouterLink>
      <button
        v-else
        type="button"
        data-test="log-in"
        class="rounded bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800 disabled:opacity-50"
        :disabled="working"
        @click="logIn"
      >
        {{ working ? $t('login.working') : $t('login.button') }}
      </button>
      <p class="text-sm text-slate-500">{{ $t('login.duration') }}</p>
    </template>

    <template v-else>
      <p class="text-slate-600">{{ $t('login.intro') }}</p>
      <form class="space-y-3" novalidate @submit.prevent="askForLink">
        <label class="block space-y-1">
          <span class="text-sm font-semibold text-slate-700">{{ $t('login.email') }}</span>
          <input
            v-model="email"
            type="email"
            name="email"
            autocomplete="email"
            class="block w-full rounded border border-slate-300 bg-white px-3 py-2"
            :aria-invalid="invalidEmail"
          />
        </label>
        <p v-if="invalidEmail" data-test="invalid" class="text-sm text-red-800">{{ $t('login.invalidEmail') }}</p>
        <button
          type="submit"
          class="rounded bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800 disabled:opacity-50"
          :disabled="working"
        >
          {{ working ? $t('login.sending') : $t('login.send') }}
        </button>
      </form>

      <ErrorNote v-if="error" :code="error" />
      <div
        v-if="sent"
        data-test="sent"
        role="status"
        class="rounded border border-emerald-200 bg-emerald-50 px-4 py-3 text-emerald-900"
      >
        <p class="font-semibold">{{ $t('login.sent') }}</p>
        <p class="text-sm">{{ $t('login.sentHint') }}</p>
      </div>
      <p class="text-sm text-slate-500">{{ $t('login.noAccess') }}</p>
    </template>
  </section>
</template>
