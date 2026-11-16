<script setup>
import { RouterLink, RouterView } from 'vue-router'

import LanguageSwitch from './components/LanguageSwitch.vue'
</script>

<template>
  <div class="min-h-screen bg-slate-50 text-slate-900">
    <header class="border-b border-slate-200 bg-white">
      <div class="mx-auto flex max-w-5xl items-center gap-6 px-4 py-3">
        <RouterLink :to="{ name: 'health' }" class="flex items-baseline gap-2" :title="$t('app.title')">
          <span class="rounded bg-emerald-700 px-2 py-0.5 text-sm font-bold tracking-wide text-white">
            {{ $t('app.short') }}
          </span>
          <span class="hidden text-sm font-semibold text-slate-700 sm:inline">{{ $t('app.title') }}</span>
        </RouterLink>
        <nav class="flex flex-1 gap-1 text-sm">
          <RouterLink
            :to="{ name: 'health' }"
            class="rounded px-3 py-1.5 text-slate-600 hover:bg-slate-100"
            exact-active-class="bg-slate-100 font-semibold text-slate-900"
          >
            {{ $t('nav.health') }}
          </RouterLink>
        </nav>
        <LanguageSwitch />
      </div>
    </header>
    <main class="mx-auto max-w-5xl px-4 py-8">
      <RouterView />
    </main>
  </div>
</template>
