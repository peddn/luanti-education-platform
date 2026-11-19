<script setup>
import { computed, onMounted } from 'vue'
import { RouterLink, RouterView, useRouter } from 'vue-router'

import LanguageSwitch from './components/LanguageSwitch.vue'
import { useAuthStore } from './stores/auth'

const auth = useAuthStore()
const router = useRouter()

// Closing the year is for the school administration only; the backend
// checks that again.
const pages = computed(() => ['overview', 'groups', ...(auth.me?.school_admin ? ['yearEnd', 'removals'] : []), 'health'])

// On a public page nobody has asked yet who is logged in.
onMounted(() => auth.load())

async function logout() {
  await auth.logout().catch(() => {})
  router.push({ name: 'login' })
}
</script>

<template>
  <div class="min-h-screen bg-slate-50 text-slate-900 print:bg-white">
    <header class="border-b border-slate-200 bg-white print:hidden">
      <div class="mx-auto flex max-w-5xl items-center gap-6 px-4 py-3">
        <RouterLink :to="{ name: 'overview' }" class="flex items-baseline gap-2" :title="$t('app.title')">
          <span class="rounded bg-emerald-700 px-2 py-0.5 text-sm font-bold tracking-wide text-white">
            {{ $t('app.short') }}
          </span>
          <span class="hidden text-sm font-semibold text-slate-700 sm:inline">{{ $t('app.title') }}</span>
        </RouterLink>
        <nav class="flex flex-1 gap-1 text-sm">
          <template v-if="auth.loggedIn">
            <RouterLink
              v-for="page in pages"
              :key="page"
              :to="{ name: page }"
              class="rounded px-3 py-1.5 text-slate-600 hover:bg-slate-100"
              :active-class="page === 'groups' ? 'bg-slate-100 font-semibold text-slate-900' : ''"
              exact-active-class="bg-slate-100 font-semibold text-slate-900"
            >
              {{ $t(`nav.${page}`) }}
            </RouterLink>
          </template>
        </nav>
        <div v-if="auth.me" class="flex items-center gap-3 text-sm">
          <span data-test="account" class="font-semibold text-slate-700">{{ auth.me.account }}</span>
          <button
            type="button"
            data-test="logout"
            class="rounded border border-slate-300 px-3 py-1 text-slate-700 hover:bg-slate-100"
            @click="logout"
          >
            {{ $t('app.logout') }}
          </button>
        </div>
        <LanguageSwitch />
      </div>
    </header>
    <main class="mx-auto max-w-5xl px-4 py-8 print:p-0">
      <RouterView />
    </main>
  </div>
</template>
