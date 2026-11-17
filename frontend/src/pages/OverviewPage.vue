<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const { locale } = useI18n()

// The browser writes the time in the chosen language.
const until = computed(() =>
  auth.me
    ? new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium', timeStyle: 'short' }).format(
        new Date(auth.me.expires_at * 1000),
      )
    : '',
)
</script>

<template>
  <section v-if="auth.me" class="space-y-6">
    <div>
      <h1 class="text-2xl font-bold">{{ $t('overview.title') }}</h1>
      <p class="mt-1 text-slate-600">{{ $t('overview.welcome', { account: auth.me.account }) }}</p>
    </div>

    <dl class="grid max-w-xl grid-cols-[auto_1fr] gap-x-8 gap-y-3 rounded border border-slate-200 bg-white p-5">
      <dt class="text-slate-500">{{ $t('overview.account') }}</dt>
      <dd data-test="account" class="font-semibold">{{ auth.me.account }}</dd>
      <dt class="text-slate-500">{{ $t('overview.email') }}</dt>
      <dd data-test="email">{{ auth.me.email }}</dd>
      <dt class="text-slate-500">{{ $t('overview.worlds') }}</dt>
      <dd data-test="worlds">{{ auth.me.worlds.join(', ') }}</dd>
      <dt class="text-slate-500">{{ $t('overview.until') }}</dt>
      <dd data-test="until">{{ until }}</dd>
    </dl>

    <p class="text-slate-500">{{ $t('overview.soon') }}</p>
  </section>
</template>
