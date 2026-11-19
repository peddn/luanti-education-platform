<script setup>
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink } from 'vue-router'

import { api, errorCode } from '@/api/client'
import AccessSlips from '@/components/AccessSlips.vue'
import ErrorNote from '@/components/ErrorNote.vue'
import LiveNote from '@/components/LiveNote.vue'
import { useGroupChanges } from '@/composables/groupChanges'

/** @typedef {import('@/api/client').Group} Group */
/** @typedef {import('@/api/client').Student} Student */
/** @typedef {import('@/api/client').AccessSlip} AccessSlip */
/** @typedef {import('@/api/client').DisplayNameEntry} DisplayNameEntry */
/** @typedef {import('@/api/client').ErrorCode} ErrorCode */

const props = defineProps({
  /** Identifier of the group, from the address. */
  id: { type: String, required: true },
})

const group = ref(/** @type {Group | null} */ (null))
const students = ref(/** @type {Student[]} */ ([]))
const loadError = ref(/** @type {ErrorCode | null} */ (null))

const count = ref('1')
const invalidCount = ref(false)
const busy = ref(false)
const error = ref(/** @type {ErrorCode | null} */ (null))

// The slips with the passwords, only in the memory of this page.
const slips = ref(/** @type {AccessSlip[] | null} */ (null))
// True if the slips are for a new password of an account that exists.
const slipsAreReset = ref(false)
// The account whose password is about to be reset, after the first click.
const resetting = ref(/** @type {string | null} */ (null))

// What the list is narrowed to: a part of an account or display name.
const search = ref('')
// The account whose history of display names is shown, with the history.
const history = ref(/** @type {{ account: string, entries: DisplayNameEntry[] } | null} */ (null))

const { locale } = useI18n()

const shown = computed(() => {
  const wanted = search.value.trim().toLocaleLowerCase()
  if (wanted === '') {
    return students.value
  }
  return students.value.filter(
    (student) =>
      student.account.toLocaleLowerCase().includes(wanted) ||
      (student.display_name ?? '').toLocaleLowerCase().includes(wanted),
  )
})

/**
 * Writes a day in the chosen language.
 *
 * @param {number} at seconds since 1970
 */
function day(at) {
  return new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium' }).format(new Date(at * 1000))
}

const drafts = computed(() => students.value.filter((student) => student.state === 'draft'))
const anyRefused = computed(() => students.value.some((student) => student.state === 'refused'))
const anyCreating = computed(() => students.value.some((student) => student.state === 'creating'))

/** @param {Student} student */
function changeable(student) {
  return student.state === 'draft' || student.state === 'refused'
}

async function load() {
  try {
    group.value = await api.group(props.id)
    students.value = await api.students(props.id)
    loadError.value = null
  } catch (err) {
    loadError.value = errorCode(err)
  }
}

onMounted(load)

/**
 * Runs a change and shows the list it returns.
 *
 * @param {() => Promise<Student[]>} change
 */
async function apply(change) {
  busy.value = true
  error.value = null
  try {
    students.value = await change()
  } catch (err) {
    error.value = errorCode(err)
  } finally {
    busy.value = false
  }
}

function roll() {
  const wanted = Number(count.value)
  invalidCount.value = !Number.isInteger(wanted) || wanted < 1 || wanted > 40
  if (!invalidCount.value) {
    apply(() => api.draftStudents(props.id, wanted))
  }
}

/** @param {string} account */
function reroll(account) {
  apply(() => api.rerollStudent(props.id, account))
}

/** @param {string} account */
function remove(account) {
  apply(() => api.removeStudent(props.id, account))
}

/** @param {string} account */
async function resetPassword(account) {
  busy.value = true
  error.value = null
  try {
    slips.value = await api.resetPassword(props.id, account)
    slipsAreReset.value = true
    resetting.value = null
  } catch (err) {
    error.value = errorCode(err)
  } finally {
    busy.value = false
  }
}

/** @param {string} account */
function removeDisplayName(account) {
  apply(() => api.removeDisplayName(props.id, account))
}

/**
 * @param {string} account
 * @param {boolean} locked
 */
function lockDisplayName(account, locked) {
  apply(() => api.lockDisplayName(props.id, account, locked))
}

/** @param {string} account */
async function toggleHistory(account) {
  if (history.value?.account === account) {
    history.value = null
    return
  }
  busy.value = true
  error.value = null
  try {
    history.value = {
      account,
      entries: await api.displayNameHistory(props.id, account),
    }
  } catch (err) {
    error.value = errorCode(err)
  } finally {
    busy.value = false
  }
}

async function create() {
  busy.value = true
  error.value = null
  try {
    slips.value = await api.createStudents(props.id)
    slipsAreReset.value = false
    students.value = await api.students(props.id)
  } catch (err) {
    error.value = errorCode(err)
  } finally {
    busy.value = false
  }
}

// Loads the list again after the backend said it changed, and the
// history that is open. What the user typed stays, and a lost connection
// leaves the list as it is.
async function refresh() {
  try {
    students.value = await api.students(props.id)
    if (history.value) {
      const account = history.value.account
      const entries = await api.displayNameHistory(props.id, account)
      if (history.value?.account === account) {
        history.value = { account, entries }
      }
    }
  } catch (err) {
    if (errorCode(err) !== 'network') {
      loadError.value = errorCode(err)
    }
  }
}

// While the slips with the passwords are shown nothing is loaded: they
// exist only in this page.
const { live } = useGroupChanges(props.id, ['students'], refresh, () => slips.value !== null)

function closeSlips() {
  slips.value = null
  load()
}
</script>

<template>
  <section class="space-y-6">
    <RouterLink :to="{ name: 'group', params: { id } }" class="text-sm text-emerald-700 underline print:hidden">
      {{ $t('students.back') }}
    </RouterLink>

    <ErrorNote v-if="loadError" :code="loadError" />
    <p v-else-if="!group" class="text-slate-500">
      {{ $t('students.loading') }}
    </p>

    <AccessSlips
      v-else-if="slips"
      :slips="slips"
      :address="group.address ?? ''"
      :reset="slipsAreReset"
      @done="closeSlips"
    />

    <template v-else>
      <div>
        <h1 class="text-2xl font-bold">
          {{ $t('students.titleFor', { group: group.name }) }}
        </h1>
        <p class="mt-1 text-slate-600">{{ $t('students.intro') }}</p>
      </div>

      <LiveNote :live="live" />
      <ErrorNote v-if="error" :code="error" />

      <p v-if="students.length === 0" data-test="empty" class="text-slate-500">
        {{ $t('students.empty') }}
      </p>
      <template v-else>
        <label class="block max-w-sm space-y-1">
          <span class="block text-sm text-slate-600">{{ $t('students.search') }}</span>
          <input
            v-model="search"
            type="search"
            name="search"
            class="block w-full rounded border border-slate-300 bg-white px-3 py-2"
          />
        </label>
        <p v-if="shown.length === 0" data-test="no-match" class="text-slate-500">
          {{ $t('students.noMatch') }}
        </p>
        <table v-else class="w-full max-w-5xl border-collapse rounded border border-slate-200 bg-white text-left">
          <thead class="border-b border-slate-200 text-sm text-slate-500">
            <tr>
              <th class="px-4 py-2 font-semibold">
                {{ $t('students.account') }}
              </th>
              <th class="px-4 py-2 font-semibold">
                {{ $t('students.displayName') }}
              </th>
              <th class="px-4 py-2 font-semibold">
                {{ $t('students.state') }}
              </th>
              <th class="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody>
            <template v-for="student in shown" :key="student.account">
              <tr data-test="student" class="border-b border-slate-100 align-top">
                <td class="px-4 py-2 font-mono font-semibold">
                  {{ student.account }}
                </td>
                <td class="px-4 py-2" data-test="display-name">
                  <template v-if="student.state === 'active'">
                    <span v-if="student.display_name" class="font-semibold">{{ student.display_name }}</span>
                    <span v-else class="text-slate-500">{{ $t('students.noDisplayName') }}</span>
                    <span
                      v-if="student.display_name && student.display_changed_at"
                      class="block text-sm text-slate-600"
                    >
                      {{
                        $t('students.displaySince', {
                          day: day(student.display_changed_at),
                        })
                      }}
                    </span>
                    <span v-if="student.display_locked" data-test="display-locked" class="block text-sm text-slate-600">
                      {{ $t('students.displayLocked') }}
                    </span>
                    <span
                      v-if="student.display_change"
                      data-test="display-change"
                      class="block text-sm"
                      :class="student.display_change === 'refused' ? 'text-red-800' : 'text-amber-700'"
                    >
                      {{ $t(`students.displayChange.${student.display_change}`) }}
                    </span>
                  </template>
                </td>
                <td class="px-4 py-2" :class="student.state === 'refused' ? 'text-red-800' : 'text-slate-600'">
                  {{ $t(`students.states.${student.state}`) }}
                  <span
                    v-if="student.password"
                    data-test="password-state"
                    class="block text-sm"
                    :class="student.password === 'refused' ? 'text-red-800' : 'text-amber-700'"
                  >
                    {{ $t(`students.password.${student.password}`) }}
                  </span>
                </td>
                <td class="space-x-3 px-4 py-2 text-right text-sm">
                  <template v-if="student.state === 'active'">
                    <template v-if="resetting === student.account">
                      <span class="text-slate-600">{{ $t('students.resetConfirm') }}</span>
                      <button
                        type="button"
                        data-test="reset-yes"
                        class="font-semibold text-red-800 underline"
                        :disabled="busy"
                        @click="resetPassword(student.account)"
                      >
                        {{ $t('students.resetYes') }}
                      </button>
                      <button type="button" class="text-slate-600 underline" @click="resetting = null">
                        {{ $t('students.resetNo') }}
                      </button>
                    </template>
                    <button
                      v-else
                      type="button"
                      data-test="reset"
                      class="text-emerald-700 underline"
                      :disabled="busy"
                      @click="resetting = student.account"
                    >
                      {{ $t('students.reset') }}
                    </button>
                    <button
                      v-if="student.display_name"
                      type="button"
                      data-test="display-remove"
                      class="text-emerald-700 underline"
                      :disabled="busy"
                      @click="removeDisplayName(student.account)"
                    >
                      {{ $t('students.displayRemove') }}
                    </button>
                    <button
                      type="button"
                      data-test="display-lock"
                      class="text-emerald-700 underline"
                      :disabled="busy"
                      @click="lockDisplayName(student.account, !student.display_locked)"
                    >
                      {{ student.display_locked ? $t('students.displayUnlock') : $t('students.displayLock') }}
                    </button>
                    <button
                      type="button"
                      data-test="display-history"
                      class="text-emerald-700 underline"
                      :disabled="busy"
                      :aria-expanded="history?.account === student.account"
                      @click="toggleHistory(student.account)"
                    >
                      {{ $t('students.history') }}
                    </button>
                  </template>
                  <template v-if="changeable(student)">
                    <button
                      type="button"
                      class="text-emerald-700 underline"
                      :disabled="busy"
                      @click="reroll(student.account)"
                    >
                      {{ $t('students.reroll') }}
                    </button>
                    <button
                      type="button"
                      class="text-slate-600 underline"
                      :disabled="busy"
                      @click="remove(student.account)"
                    >
                      {{ $t('students.remove') }}
                    </button>
                  </template>
                </td>
              </tr>
              <tr
                v-if="history && history.account === student.account"
                data-test="history"
                class="border-b border-slate-200 bg-slate-50"
              >
                <td colspan="4" class="space-y-2 px-4 py-3 text-sm">
                  <h2 class="font-semibold">
                    {{ $t('students.historyTitle', { account: student.account }) }}
                  </h2>
                  <p v-if="history.entries.length === 0" class="text-slate-500">
                    {{ $t('students.historyEmpty') }}
                  </p>
                  <ul v-else class="space-y-1">
                    <li v-for="(entry, index) in history.entries" :key="index">
                      {{
                        $t(`students.historyActions.${entry.action}`, {
                          day: day(entry.time),
                          name: entry.name ?? '',
                          by: entry.by,
                        })
                      }}
                    </li>
                  </ul>
                  <p class="text-slate-500">{{ $t('students.historyHint') }}</p>
                </td>
              </tr>
            </template>
          </tbody>
        </table>
      </template>

      <p v-if="anyRefused" data-test="refused-hint" class="max-w-2xl text-sm text-red-800">
        {{ $t('students.refusedHint') }}
      </p>
      <p v-if="anyCreating" data-test="pending-hint" class="max-w-2xl text-sm text-slate-600">
        {{ $t('students.pendingHint') }}
      </p>

      <button
        v-if="drafts.length > 0"
        type="button"
        data-test="create"
        class="rounded bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800 disabled:opacity-50"
        :disabled="busy"
        @click="create"
      >
        {{ busy ? $t('students.creating') : $t('students.create', drafts.length) }}
      </button>

      <form class="max-w-2xl space-y-3 rounded border border-slate-200 bg-white p-5" novalidate @submit.prevent="roll">
        <h2 class="font-semibold">{{ $t('students.draftTitle') }}</h2>
        <p class="text-sm text-slate-500">{{ $t('students.draftHint') }}</p>
        <div class="flex items-end gap-3">
          <label class="space-y-1">
            <span class="block text-sm text-slate-600">{{ $t('students.count') }}</span>
            <input
              v-model="count"
              type="number"
              name="count"
              min="1"
              max="40"
              class="block w-24 rounded border border-slate-300 bg-white px-3 py-2"
              :aria-invalid="invalidCount"
            />
          </label>
          <button
            type="submit"
            class="rounded border border-emerald-700 px-4 py-2 text-sm font-semibold text-emerald-800 hover:bg-emerald-50 disabled:opacity-50"
            :disabled="busy"
          >
            {{ $t('students.roll') }}
          </button>
        </div>
        <p v-if="invalidCount" data-test="invalid" class="text-sm text-red-800">
          {{ $t('students.invalidCount') }}
        </p>
      </form>
    </template>
  </section>
</template>
