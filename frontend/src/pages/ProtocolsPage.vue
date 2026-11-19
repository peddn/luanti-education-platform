<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink } from 'vue-router'

import { api, errorCode } from '@/api/client'
import ErrorNote from '@/components/ErrorNote.vue'
import LiveNote from '@/components/LiveNote.vue'
import { useGroupChanges } from '@/composables/groupChanges'
import { useAuthStore } from '@/stores/auth'

/** @typedef {import('@/api/client').Group} Group */
/** @typedef {import('@/api/client').ProtocolRow} ProtocolRow */
/** @typedef {import('@/api/client').ErrorCode} ErrorCode */

const props = defineProps({
  /** Identifier of the group, from the address. */
  id: { type: String, required: true },
  /** The protocol to start with, from the address. */
  startProtocol: { type: String, default: 'chat' },
  /** The account to start with, from the address. */
  startAccount: { type: String, default: '' },
})

const { locale, t, te } = useI18n()
const auth = useAuthStore()

// The protocol of the desk shows what teachers did. Only the school
// administration reads it; the backend checks that again.
const names = computed(() =>
  ['chat', 'signs', 'rewards', 'names', 'desk'].filter((name) => name !== 'desk' || auth.me?.school_admin === true),
)
const PERIODS = ['all', 'today', 'week', 'month']
// Columns whose values are fixed words that have a translation.
const WORDS = ['kind', 'size', 'reason', 'action']

const group = ref(/** @type {Group | null} */ (null))
const accounts = ref(/** @type {string[]} */ ([]))
const loadError = ref(/** @type {ErrorCode | null} */ (null))
const error = ref(/** @type {ErrorCode | null} */ (null))
const busy = ref(false)

const protocol = ref(names.value.includes(props.startProtocol) ? props.startProtocol : 'chat')
const account = ref(props.startAccount)
const period = ref('all')

const columns = ref(/** @type {string[]} */ ([]))
const entries = ref(/** @type {ProtocolRow[]} */ ([]))
const more = ref(false)
// Entries that arrived while the page was open. They are shown on a
// click only, so the lines do not move while somebody reads.
const waiting = ref(/** @type {ProtocolRow[]} */ ([]))
// True if more arrived than one request returns.
const waitingMore = ref(false)

/** The filters as the backend takes them. */
function filters() {
  const now = new Date()
  /** @type {number | undefined} */
  let since
  if (period.value === 'today') {
    since = Math.floor(new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime() / 1000)
  } else if (period.value === 'week') {
    since = Math.floor(now.getTime() / 1000) - 7 * 86400
  } else if (period.value === 'month') {
    since = Math.floor(now.getTime() / 1000) - 30 * 86400
  }
  return { account: account.value.trim() || undefined, since }
}

const exportUrl = computed(() => api.protocolExportUrl(props.id, protocol.value, filters()))

async function load() {
  busy.value = true
  error.value = null
  try {
    const page = await api.protocol(props.id, protocol.value, filters())
    columns.value = page.columns
    entries.value = page.entries
    more.value = page.more
    waiting.value = []
    waitingMore.value = false
  } catch (err) {
    error.value = errorCode(err)
  } finally {
    busy.value = false
  }
}

onMounted(async () => {
  try {
    group.value = await api.group(props.id)
    const students = await api.students(props.id)
    accounts.value = students.filter((student) => student.state === 'active').map((student) => student.account)
  } catch (err) {
    loadError.value = errorCode(err)
    return
  }
  await load()
})

watch([protocol, period], load)

async function loadMore() {
  const last = entries.value.at(-1)
  if (!last) {
    return
  }
  busy.value = true
  error.value = null
  try {
    const page = await api.protocol(props.id, protocol.value, { ...filters(), before: last.id })
    entries.value = [...entries.value, ...page.entries]
    more.value = page.more
  } catch (err) {
    error.value = errorCode(err)
  } finally {
    busy.value = false
  }
}

// Asks what arrived since the newest entry that is shown or waiting.
async function checkNew() {
  const newest = waiting.value[0] ?? entries.value[0]
  try {
    const page = await api.protocol(props.id, protocol.value, { ...filters(), after: newest?.id ?? 0 })
    if (page.entries.length > 0) {
      waiting.value = [...page.entries, ...waiting.value]
      waitingMore.value = waitingMore.value || page.more
    }
  } catch {
    // The next signal asks again; the page stays as it is.
  }
}

function showWaiting() {
  if (waitingMore.value) {
    // Too many for one request: start over with the newest.
    load()
    return
  }
  entries.value = [...waiting.value, ...entries.value]
  waiting.value = []
}

const { live } = useGroupChanges(props.id, ['protocols'], checkNew)

/**
 * Writes a time in the chosen language.
 *
 * @param {number} at seconds since 1970
 */
function time(at) {
  return new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium', timeStyle: 'medium' }).format(new Date(at * 1000))
}

/**
 * Returns a cell as it is shown: fixed words in the chosen language,
 * everything else as it was written.
 *
 * @param {string} column
 * @param {string | undefined} value
 */
function shown(column, value) {
  if (value === undefined || value === '') {
    return ''
  }
  const key = `protocols.values.${column}.${value}`
  return WORDS.includes(column) && te(key) ? t(key) : value
}
</script>

<template>
  <section class="space-y-6">
    <RouterLink :to="{ name: 'group', params: { id } }" class="text-sm text-emerald-700 underline">
      {{ $t('protocols.back') }}
    </RouterLink>

    <ErrorNote v-if="loadError" :code="loadError" />
    <p v-else-if="!group" class="text-slate-500">{{ $t('protocols.loading') }}</p>

    <template v-else>
      <div>
        <h1 class="text-2xl font-bold">{{ $t('protocols.titleFor', { group: group.name }) }}</h1>
        <p class="mt-1 max-w-3xl text-slate-600">{{ $t('protocols.intro') }}</p>
      </div>

      <nav class="flex flex-wrap gap-2" :aria-label="$t('protocols.tabsLabel')">
        <button
          v-for="name in names"
          :key="name"
          type="button"
          data-test="tab"
          class="rounded border px-3 py-1.5 text-sm font-semibold"
          :class="
            name === protocol
              ? 'border-emerald-700 bg-emerald-700 text-white'
              : 'border-slate-300 bg-white text-slate-700 hover:bg-emerald-50'
          "
          :aria-pressed="name === protocol"
          @click="protocol = name"
        >
          {{ $t(`protocols.tabs.${name}`) }}
        </button>
      </nav>

      <form class="flex flex-wrap items-end gap-4" novalidate @submit.prevent="load">
        <label class="space-y-1">
          <span class="block text-sm text-slate-600">{{ $t('protocols.account') }}</span>
          <input
            v-model="account"
            type="search"
            name="account"
            list="protocol-accounts"
            class="block w-56 rounded border border-slate-300 bg-white px-3 py-2"
          />
          <datalist id="protocol-accounts">
            <option v-for="name in accounts" :key="name" :value="name"></option>
          </datalist>
        </label>
        <label class="space-y-1">
          <span class="block text-sm text-slate-600">{{ $t('protocols.period') }}</span>
          <select v-model="period" name="period" class="block rounded border border-slate-300 bg-white px-3 py-2">
            <option v-for="name in PERIODS" :key="name" :value="name">{{ $t(`protocols.periods.${name}`) }}</option>
          </select>
        </label>
        <button
          type="submit"
          data-test="apply"
          class="rounded bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800 disabled:opacity-50"
          :disabled="busy"
        >
          {{ $t('protocols.apply') }}
        </button>
        <a
          :href="exportUrl"
          download
          data-test="export"
          class="rounded border border-emerald-700 px-4 py-2 text-sm font-semibold text-emerald-800 hover:bg-emerald-50"
        >
          {{ $t('protocols.export') }}
        </a>
      </form>
      <p class="max-w-3xl text-sm text-slate-500">{{ $t('protocols.exportHint') }}</p>

      <LiveNote :live="live" />
      <ErrorNote v-if="error" :code="error" />

      <button
        v-if="waiting.length > 0"
        type="button"
        data-test="waiting"
        class="rounded border border-amber-600 bg-amber-50 px-4 py-2 text-sm font-semibold text-amber-800"
        @click="showWaiting"
      >
        {{ waitingMore ? $t('protocols.waitingMany') : $t('protocols.waiting', waiting.length) }}
      </button>

      <p v-if="entries.length === 0" data-test="empty" class="text-slate-500">{{ $t('protocols.empty') }}</p>
      <table v-else class="w-full border-collapse rounded border border-slate-200 bg-white text-left text-sm">
        <thead class="border-b border-slate-200 text-slate-500">
          <tr>
            <th class="px-3 py-2 font-semibold">{{ $t('protocols.time') }}</th>
            <th class="px-3 py-2 font-semibold">{{ $t('protocols.columns.account') }}</th>
            <th v-for="column in columns" :key="column" class="px-3 py-2 font-semibold">
              {{ $t(`protocols.columns.${column}`) }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="entry in entries" :key="entry.id" data-test="entry" class="border-b border-slate-100 align-top">
            <td class="px-3 py-2 whitespace-nowrap text-slate-600">{{ time(entry.time) }}</td>
            <td class="px-3 py-2">
              <span class="block font-mono font-semibold">{{ entry.account }}</span>
              <span v-if="entry.display_name" class="block text-slate-600">{{ entry.display_name }}</span>
            </td>
            <td v-for="column in columns" :key="column" class="px-3 py-2 break-words">
              {{ shown(column, entry.fields[column]) }}
            </td>
          </tr>
        </tbody>
      </table>

      <button
        v-if="more"
        type="button"
        data-test="more"
        class="rounded border border-emerald-700 px-4 py-2 text-sm font-semibold text-emerald-800 hover:bg-emerald-50 disabled:opacity-50"
        :disabled="busy"
        @click="loadMore"
      >
        {{ $t('protocols.more') }}
      </button>
    </template>
  </section>
</template>
