<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink } from 'vue-router'

import { api, errorCode } from '@/api/client'
import ErrorNote from '@/components/ErrorNote.vue'

/** @typedef {import('@/api/client').YearEnd} YearEnd */
/** @typedef {import('@/api/client').ErrorCode} ErrorCode */

// How often the page asks while worlds have not deleted yet.
const ASK_AGAIN_MS = 3000

const { locale, t } = useI18n()

const state = ref(/** @type {YearEnd | null} */ (null))
const loadError = ref(/** @type {ErrorCode | null} */ (null))
const error = ref(/** @type {ErrorCode | null} */ (null))
const busy = ref(false)
const done = ref(false)
// What the user typed to confirm.
const typed = ref('')

const word = computed(() => t('yearEnd.word'))
const confirmed = computed(() => typed.value.trim() === word.value)
const waiting = computed(() => state.value?.groups.some((group) => group.world === 'pending') ?? false)

/** @type {ReturnType<typeof setInterval> | undefined} */
let timer

async function load() {
  try {
    state.value = await api.yearEnd()
    loadError.value = null
  } catch (err) {
    // A lost connection leaves what is shown.
    if (state.value === null || errorCode(err) !== 'network') {
      loadError.value = errorCode(err)
    }
  }
}

onMounted(async () => {
  await load()
  // The worlds delete when they answer; that can take a while.
  timer = setInterval(() => {
    if (waiting.value) {
      load()
    }
  }, ASK_AGAIN_MS)
})

onUnmounted(() => clearInterval(timer))

async function close() {
  if (!confirmed.value) {
    return
  }
  busy.value = true
  error.value = null
  try {
    state.value = await api.closeYear()
    typed.value = ''
    done.value = true
  } catch (err) {
    error.value = errorCode(err)
  } finally {
    busy.value = false
  }
}

/**
 * Writes a day in the chosen language.
 *
 * @param {number} at seconds since 1970
 */
function day(at) {
  return new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(at * 1000))
}
</script>

<template>
  <section class="space-y-6">
    <ErrorNote v-if="loadError" :code="loadError" />
    <p v-else-if="!state" class="text-slate-500">{{ $t('yearEnd.loading') }}</p>

    <template v-else>
      <div>
        <h1 class="text-2xl font-bold">{{ $t('yearEnd.title') }}</h1>
        <p class="mt-1 max-w-3xl text-slate-600">{{ $t('yearEnd.intro') }}</p>
      </div>

      <div class="grid max-w-4xl gap-4 sm:grid-cols-2">
        <div class="rounded border border-slate-200 bg-white p-4">
          <h2 class="font-semibold">{{ $t('yearEnd.deletedTitle') }}</h2>
          <p class="mt-1 text-sm text-slate-600">{{ $t('yearEnd.deleted') }}</p>
        </div>
        <div class="rounded border border-slate-200 bg-white p-4">
          <h2 class="font-semibold">{{ $t('yearEnd.keptTitle') }}</h2>
          <p class="mt-1 text-sm text-slate-600">{{ $t('yearEnd.kept') }}</p>
        </div>
      </div>
      <p class="max-w-3xl text-sm text-slate-500">{{ $t('yearEnd.later') }}</p>

      <p v-if="state.groups.length === 0" data-test="no-groups" class="text-slate-500">{{ $t('yearEnd.noGroups') }}</p>
      <table v-else class="w-full max-w-4xl border-collapse rounded border border-slate-200 bg-white text-left">
        <thead class="border-b border-slate-200 text-sm text-slate-500">
          <tr>
            <th class="px-4 py-2 font-semibold">{{ $t('yearEnd.group') }}</th>
            <th class="px-4 py-2 font-semibold">{{ $t('yearEnd.entries') }}</th>
            <th class="px-4 py-2 font-semibold">{{ $t('yearEnd.exports') }}</th>
            <th class="px-4 py-2 font-semibold">{{ $t('yearEnd.world') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="group in state.groups" :key="group.id" data-test="group" class="border-b border-slate-100 last:border-0">
            <td class="px-4 py-2">
              <span class="font-semibold">{{ group.name }}</span>
              <RouterLink
                :to="{ name: 'protocols', params: { id: group.id } }"
                class="ml-3 text-sm text-emerald-700 underline"
              >
                {{ $t('yearEnd.look') }}
              </RouterLink>
            </td>
            <td class="px-4 py-2">{{ group.protocol_entries }}</td>
            <td class="px-4 py-2">{{ group.exports }}</td>
            <td class="px-4 py-2 text-sm" :class="group.world === 'refused' ? 'text-red-800' : 'text-amber-700'">
              {{ group.world ? $t(`yearEnd.worldStates.${group.world}`) : '' }}
            </td>
          </tr>
        </tbody>
      </table>

      <p v-if="done" data-test="done" role="status" class="max-w-3xl rounded border border-emerald-700 bg-emerald-50 p-4 text-emerald-900">
        {{ $t('yearEnd.done') }}
      </p>
      <ErrorNote v-if="error" :code="error" />

      <form class="max-w-3xl space-y-3 rounded border border-red-300 bg-white p-5" novalidate @submit.prevent="close">
        <h2 class="font-semibold text-red-800">{{ $t('yearEnd.closeTitle') }}</h2>
        <p class="text-sm text-slate-600">{{ $t('yearEnd.warning') }}</p>
        <label class="block space-y-1">
          <span class="block text-sm text-slate-600">{{ $t('yearEnd.typeWord', { word }) }}</span>
          <input
            v-model="typed"
            type="text"
            name="confirm"
            autocomplete="off"
            class="block w-56 rounded border border-slate-300 bg-white px-3 py-2"
          />
        </label>
        <button
          type="submit"
          data-test="close"
          class="rounded bg-red-700 px-4 py-2 text-sm font-semibold text-white hover:bg-red-800 disabled:opacity-40"
          :disabled="busy || !confirmed"
        >
          {{ $t('yearEnd.close') }}
        </button>
      </form>

      <div class="max-w-3xl">
        <h2 class="font-semibold">{{ $t('yearEnd.runsTitle') }}</h2>
        <p v-if="state.runs.length === 0" class="mt-1 text-sm text-slate-500">{{ $t('yearEnd.noRuns') }}</p>
        <ul v-else class="mt-1 space-y-1 text-sm text-slate-700">
          <li v-for="run in state.runs" :key="run.time" data-test="run">
            {{
              $t('yearEnd.run', {
                day: day(run.time),
                account: run.account,
                entries: run.protocol_entries,
                exports: run.exports,
                groups: run.groups,
              })
            }}
          </li>
        </ul>
      </div>
    </template>
  </section>
</template>
