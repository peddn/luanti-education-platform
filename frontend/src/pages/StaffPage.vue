<script setup>
import { onMounted, onUnmounted, ref } from 'vue'

import { api, errorCode } from '@/api/client'
import AccessSlips from '@/components/AccessSlips.vue'
import ErrorNote from '@/components/ErrorNote.vue'
import { useAuthStore } from '@/stores/auth'

/** @typedef {import('@/api/client').StaffAccount} StaffAccount */
/** @typedef {import('@/api/client').AccessSlip} AccessSlip */
/** @typedef {import('@/api/client').ErrorCode} ErrorCode */

// How often the page asks while a world has not answered yet.
const ASK_AGAIN_MS = 3000

const auth = useAuthStore()

const staff = ref(/** @type {StaffAccount[] | null} */ (null))
const loadError = ref(/** @type {ErrorCode | null} */ (null))
const error = ref(/** @type {ErrorCode | null} */ (null))
const busy = ref(false)

const name = ref('')
const invalidName = ref(false)

// The slip with the password, only in the memory of this page.
const slips = ref(/** @type {AccessSlip[] | null} */ (null))
// True if the slip is for a new password of an account that exists.
const slipsAreReset = ref(false)
// The account whose password is about to be reset, after the first click.
const resetting = ref(/** @type {string | null} */ (null))
// The account that is about to be deleted, and what was typed to
// confirm it.
const removing = ref(/** @type {string | null} */ (null))
const typed = ref('')

/**
 * Accounts of the school administration and the own account are never
 * changed from here. The backend and the worlds check it again.
 *
 * @param {StaffAccount} entry
 */
function changeable(entry) {
  return !entry.school_admin && entry.account !== auth.me?.account
}

/** @param {StaffAccount} entry */
function waits(entry) {
  return entry.state === 'creating' || entry.password === 'pending' || entry.removal === 'pending'
}

async function load() {
  try {
    staff.value = await api.staff()
    loadError.value = null
  } catch (err) {
    // A lost connection leaves what is shown.
    if (staff.value === null || errorCode(err) !== 'network') {
      loadError.value = errorCode(err)
    }
  }
}

/** @type {ReturnType<typeof setInterval> | undefined} */
let timer

onMounted(async () => {
  await load()
  // The worlds answer when they are connected; that can take a while.
  // While a slip is shown nothing is loaded: it exists only here.
  timer = setInterval(() => {
    if (slips.value === null && staff.value?.some(waits)) {
      load()
    }
  }, ASK_AGAIN_MS)
})

onUnmounted(() => clearInterval(timer))

/**
 * Runs an order that answers with a slip and shows it.
 *
 * @param {() => Promise<AccessSlip[]>} order
 * @param {boolean} isReset
 */
async function withSlip(order, isReset) {
  busy.value = true
  error.value = null
  try {
    slips.value = await order()
    slipsAreReset.value = isReset
    resetting.value = null
    name.value = ''
  } catch (err) {
    error.value = errorCode(err)
  } finally {
    busy.value = false
  }
}

function create() {
  const wanted = name.value.trim()
  invalidName.value = !/^[A-Za-z0-9_-]{2,19}$/.test(wanted)
  if (!invalidName.value) {
    withSlip(() => api.createStaff(wanted), false)
  }
}

/** @param {string} account */
function resetPassword(account) {
  withSlip(() => api.resetStaffPassword(account), true)
}

/** @param {string} account */
function askRemoval(account) {
  removing.value = removing.value === account ? null : account
  typed.value = ''
}

async function remove() {
  const account = removing.value
  if (account === null || typed.value.trim() !== account) {
    return
  }
  busy.value = true
  error.value = null
  try {
    staff.value = await api.removeStaff(account)
    removing.value = null
    typed.value = ''
  } catch (err) {
    error.value = errorCode(err)
  } finally {
    busy.value = false
  }
}

function closeSlips() {
  slips.value = null
  load()
}
</script>

<template>
  <section class="space-y-6">
    <ErrorNote v-if="loadError" :code="loadError" />
    <p v-else-if="!staff" class="text-slate-500">{{ $t('staff.loading') }}</p>

    <AccessSlips v-else-if="slips" :slips="slips" :reset="slipsAreReset" staff @done="closeSlips" />

    <template v-else>
      <div>
        <h1 class="text-2xl font-bold">{{ $t('staff.title') }}</h1>
        <p class="mt-1 max-w-3xl text-slate-600">{{ $t('staff.intro') }}</p>
      </div>

      <ErrorNote v-if="error" :code="error" />

      <table class="w-full max-w-5xl border-collapse rounded border border-slate-200 bg-white text-left">
        <thead class="border-b border-slate-200 text-sm text-slate-500">
          <tr>
            <th class="px-4 py-2 font-semibold">{{ $t('staff.account') }}</th>
            <th class="px-4 py-2 font-semibold">{{ $t('staff.state') }}</th>
            <th class="px-4 py-2 font-semibold">{{ $t('staff.webAccess') }}</th>
            <th class="px-4 py-2 font-semibold">{{ $t('staff.groups') }}</th>
            <th class="px-4 py-2"></th>
          </tr>
        </thead>
        <tbody>
          <template v-for="entry in staff" :key="entry.account">
            <tr data-test="teacher" class="border-b border-slate-100 align-top">
              <td class="px-4 py-2 font-mono font-semibold">{{ entry.account }}</td>
              <td class="px-4 py-2 text-slate-600" data-test="state">
                <span v-if="entry.school_admin" class="block">{{ $t('staff.schoolAdmin') }}</span>
                <span v-else-if="entry.state" class="block" :class="{ 'text-red-800': entry.state === 'refused' }">
                  {{ $t(`staff.states.${entry.state}`) }}
                </span>
                <span v-else class="block">{{ $t('staff.fromGame') }}</span>
                <span v-if="!entry.holder && entry.state !== 'creating' && entry.state !== 'refused'" class="block text-sm">
                  {{ $t('staff.noHolder') }}
                </span>
                <span
                  v-if="entry.password"
                  data-test="password-state"
                  class="block text-sm"
                  :class="entry.password === 'refused' ? 'text-red-800' : 'text-amber-700'"
                >
                  {{ $t(`students.password.${entry.password}`) }}
                </span>
                <span v-if="entry.removal === 'pending'" data-test="removal-state" class="block text-sm text-amber-700">
                  {{ $t('students.removalPending') }}
                </span>
                <span v-else-if="entry.removal === 'refused'" data-test="removal-state" class="block text-sm text-red-800">
                  {{ $t(`students.removalRefusals.${entry.removal_refusal ?? 'failed'}`) }}
                </span>
              </td>
              <td class="px-4 py-2 text-slate-600">{{ $t(`staff.webAccessStates.${entry.web_access}`) }}</td>
              <td class="px-4 py-2 text-slate-600">
                {{ entry.groups.length ? entry.groups.join(', ') : $t('staff.noGroups') }}
              </td>
              <td class="space-x-3 px-4 py-2 text-right text-sm">
                <template v-if="changeable(entry)">
                  <template v-if="resetting === entry.account">
                    <span class="text-slate-600">{{ $t('students.resetConfirm') }}</span>
                    <button
                      type="button"
                      data-test="reset-yes"
                      class="font-semibold text-red-800 underline"
                      :disabled="busy"
                      @click="resetPassword(entry.account)"
                    >
                      {{ $t('students.resetYes') }}
                    </button>
                    <button type="button" class="text-slate-600 underline" @click="resetting = null">
                      {{ $t('students.resetNo') }}
                    </button>
                  </template>
                  <button
                    v-else-if="entry.state !== 'creating' && entry.state !== 'refused'"
                    type="button"
                    data-test="reset"
                    class="text-emerald-700 underline"
                    :disabled="busy"
                    @click="resetting = entry.account"
                  >
                    {{ $t('students.reset') }}
                  </button>
                  <button
                    v-if="entry.removal !== 'pending'"
                    type="button"
                    data-test="removal"
                    class="text-red-800 underline"
                    :disabled="busy"
                    :aria-expanded="removing === entry.account"
                    @click="askRemoval(entry.account)"
                  >
                    {{ $t('students.removal') }}
                  </button>
                </template>
                <span v-else data-test="protected" class="text-slate-500">
                  {{ entry.school_admin ? $t('staff.protected') : $t('staff.own') }}
                </span>
              </td>
            </tr>
            <tr
              v-if="removing === entry.account && changeable(entry)"
              data-test="removal-form"
              class="border-b border-slate-200 bg-red-50"
            >
              <td colspan="5" class="px-4 py-4 text-sm">
                <form class="max-w-3xl space-y-3" novalidate @submit.prevent="remove">
                  <h2 class="font-semibold text-red-800">
                    {{ $t('students.removalTitle', { account: entry.account }) }}
                  </h2>
                  <p>{{ $t('staff.removalIntro') }}</p>
                  <p class="text-slate-600">{{ $t('staff.removalKept') }}</p>
                  <label class="block space-y-1">
                    <span class="block text-slate-600">{{ $t('students.removalType', { account: entry.account }) }}</span>
                    <input
                      v-model="typed"
                      type="text"
                      name="confirm"
                      autocomplete="off"
                      class="block w-64 rounded border border-slate-300 bg-white px-3 py-2 font-mono"
                    />
                  </label>
                  <div class="space-x-3">
                    <button
                      type="submit"
                      data-test="removal-yes"
                      class="rounded bg-red-700 px-4 py-2 font-semibold text-white hover:bg-red-800 disabled:opacity-40"
                      :disabled="busy || typed.trim() !== entry.account"
                    >
                      {{ $t('students.removalYes') }}
                    </button>
                    <button type="button" class="text-slate-600 underline" @click="askRemoval(entry.account)">
                      {{ $t('students.resetNo') }}
                    </button>
                  </div>
                </form>
              </td>
            </tr>
          </template>
        </tbody>
      </table>

      <form class="max-w-2xl space-y-3 rounded border border-slate-200 bg-white p-5" novalidate @submit.prevent="create">
        <h2 class="font-semibold">{{ $t('staff.createTitle') }}</h2>
        <p class="text-sm text-slate-500">{{ $t('staff.createHint') }}</p>
        <div class="flex items-end gap-3">
          <label class="space-y-1">
            <span class="block text-sm text-slate-600">{{ $t('staff.name') }}</span>
            <input
              v-model="name"
              type="text"
              name="name"
              autocomplete="off"
              maxlength="19"
              class="block w-64 rounded border border-slate-300 bg-white px-3 py-2 font-mono"
              :aria-invalid="invalidName"
            />
          </label>
          <button
            type="submit"
            data-test="create"
            class="rounded bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800 disabled:opacity-50"
            :disabled="busy"
          >
            {{ $t('staff.create') }}
          </button>
        </div>
        <p v-if="invalidName" data-test="invalid" class="text-sm text-red-800">{{ $t('staff.invalidName') }}</p>
      </form>

      <p class="max-w-3xl text-sm text-slate-500">{{ $t('staff.hint') }}</p>
    </template>
  </section>
</template>
