<script setup>
import { computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'

import ErrorNote from '@/components/ErrorNote.vue'
import { useHealthStore } from '@/stores/health'

const store = useHealthStore()
const { locale } = useI18n()

const server = computed(() => store.status?.game_server ?? null)

/**
 * Writes a time in the chosen language.
 *
 * @param {number} at seconds since 1970
 */
function time(at) {
  return new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium', timeStyle: 'medium' }).format(new Date(at * 1000))
}

/**
 * Writes an amount of bytes in gigabytes with one decimal place.
 *
 * @param {number} bytes
 */
function gigabytes(bytes) {
  return new Intl.NumberFormat(locale.value, { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(
    bytes / 1_000_000_000,
  )
}

onMounted(() => store.load())
</script>

<template>
  <section class="space-y-6">
    <div>
      <h1 class="text-2xl font-bold">{{ $t('health.title') }}</h1>
      <p class="mt-1 text-slate-600">{{ $t('health.intro') }}</p>
    </div>

    <ErrorNote v-if="store.error" :code="store.error" />

    <dl
      v-if="store.status"
      class="grid max-w-xl grid-cols-[auto_1fr] gap-x-8 gap-y-3 rounded border border-slate-200 bg-white p-5"
    >
      <dt class="text-slate-500">{{ $t('health.backend') }}</dt>
      <dd
        data-test="status"
        class="font-semibold"
        :class="store.status.status === 'ok' ? 'text-emerald-700' : 'text-amber-700'"
      >
        {{ $t(`health.status.${store.status.status}`) }}
      </dd>
      <dt class="text-slate-500">{{ $t('health.mailTitle') }}</dt>
      <dd data-test="mail">{{ $t(`health.mail.${store.status.mail}`) }}</dd>
      <dt class="text-slate-500">{{ $t('health.version') }}</dt>
      <dd data-test="version" class="font-mono">{{ store.status.version }}</dd>
    </dl>

    <p v-else-if="store.loading" class="text-slate-500">{{ $t('health.loading') }}</p>

    <div v-if="store.status" class="space-y-3">
      <div>
        <h2 class="text-lg font-semibold">{{ $t('health.server.title') }}</h2>
        <p class="mt-1 max-w-xl text-slate-600">{{ $t('health.server.intro') }}</p>
      </div>
      <dl
        v-if="server"
        class="grid max-w-xl grid-cols-[auto_1fr] gap-x-8 gap-y-3 rounded border border-slate-200 bg-white p-5"
      >
        <dt class="text-slate-500">{{ $t('health.server.state') }}</dt>
        <dd
          data-test="server-state"
          class="font-semibold"
          :class="server.connected ? 'text-emerald-700' : 'text-amber-700'"
        >
          {{ server.connected ? $t('health.server.connected') : $t('health.server.silent') }}
        </dd>
        <dt class="text-slate-500">{{ $t('health.server.lastSeen') }}</dt>
        <dd data-test="server-seen">
          {{ server.last_seen_at == null ? $t('health.server.never') : time(server.last_seen_at) }}
        </dd>
        <dt class="text-slate-500">{{ $t('health.server.agentVersion') }}</dt>
        <dd data-test="server-version" class="font-mono">{{ server.version ?? $t('health.server.unknown') }}</dd>
        <dt class="text-slate-500">{{ $t('health.server.freeDisk') }}</dt>
        <dd data-test="server-disk">
          {{
            server.free_disk_bytes == null
              ? $t('health.server.unknown')
              : $t('health.server.gigabytes', { amount: gigabytes(server.free_disk_bytes) })
          }}
        </dd>
        <dt class="text-slate-500">{{ $t('health.server.template') }}</dt>
        <dd data-test="server-template" :class="server.template ? 'font-mono' : 'text-amber-700'">
          {{ server.template ?? $t('health.server.noTemplate') }}
        </dd>
      </dl>
      <p v-else data-test="server-none" class="max-w-xl rounded border border-slate-200 bg-white p-5 text-slate-600">
        {{ $t('health.server.none') }}
      </p>
    </div>

    <button
      type="button"
      class="rounded bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800 disabled:opacity-50"
      :disabled="store.loading"
      @click="store.load()"
    >
      {{ $t('health.reload') }}
    </button>
  </section>
</template>
