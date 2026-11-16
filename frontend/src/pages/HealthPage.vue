<script setup>
import { onMounted } from 'vue'

import ErrorNote from '@/components/ErrorNote.vue'
import { useHealthStore } from '@/stores/health'

const store = useHealthStore()

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
      v-if="store.health"
      class="grid max-w-xl grid-cols-[auto_1fr] gap-x-8 gap-y-3 rounded border border-slate-200 bg-white p-5"
    >
      <dt class="text-slate-500">{{ $t('health.backend') }}</dt>
      <dd
        data-test="status"
        class="font-semibold"
        :class="store.health.status === 'ok' ? 'text-emerald-700' : 'text-amber-700'"
      >
        {{ $t(`health.status.${store.health.status}`) }}
      </dd>
      <dt class="text-slate-500">{{ $t('health.database') }}</dt>
      <dd data-test="database">
        {{ store.health.database ? $t('health.databaseOk') : $t('health.databaseDown') }}
      </dd>
      <dt class="text-slate-500">{{ $t('health.version') }}</dt>
      <dd data-test="version" class="font-mono">{{ store.health.version }}</dd>
    </dl>

    <p v-else-if="store.loading" class="text-slate-500">{{ $t('health.loading') }}</p>

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
