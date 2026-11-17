<script setup>
import { computed, onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'

import { api, errorCode } from '@/api/client'
import AccessSlips from '@/components/AccessSlips.vue'
import ErrorNote from '@/components/ErrorNote.vue'

/** @typedef {import('@/api/client').Group} Group */
/** @typedef {import('@/api/client').Student} Student */
/** @typedef {import('@/api/client').AccessSlip} AccessSlip */
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

async function create() {
  busy.value = true
  error.value = null
  try {
    slips.value = await api.createStudents(props.id)
    students.value = await api.students(props.id)
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
    <RouterLink :to="{ name: 'group', params: { id } }" class="text-sm text-emerald-700 underline print:hidden">
      {{ $t('students.back') }}
    </RouterLink>

    <ErrorNote v-if="loadError" :code="loadError" />
    <p v-else-if="!group" class="text-slate-500">{{ $t('students.loading') }}</p>

    <AccessSlips v-else-if="slips" :slips="slips" :address="group.address ?? ''" @done="closeSlips" />

    <template v-else>
      <div>
        <h1 class="text-2xl font-bold">{{ $t('students.titleFor', { group: group.name }) }}</h1>
        <p class="mt-1 text-slate-600">{{ $t('students.intro') }}</p>
      </div>

      <ErrorNote v-if="error" :code="error" />

      <p v-if="students.length === 0" data-test="empty" class="text-slate-500">{{ $t('students.empty') }}</p>
      <table v-else class="w-full max-w-2xl border-collapse rounded border border-slate-200 bg-white text-left">
        <thead class="border-b border-slate-200 text-sm text-slate-500">
          <tr>
            <th class="px-4 py-2 font-semibold">{{ $t('students.account') }}</th>
            <th class="px-4 py-2 font-semibold">{{ $t('students.state') }}</th>
            <th class="px-4 py-2"></th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="student in students"
            :key="student.account"
            data-test="student"
            class="border-b border-slate-100 last:border-0"
          >
            <td class="px-4 py-2 font-mono font-semibold">{{ student.account }}</td>
            <td class="px-4 py-2" :class="student.state === 'refused' ? 'text-red-800' : 'text-slate-600'">
              {{ $t(`students.states.${student.state}`) }}
            </td>
            <td class="space-x-3 px-4 py-2 text-right text-sm">
              <template v-if="changeable(student)">
                <button type="button" class="text-emerald-700 underline" :disabled="busy" @click="reroll(student.account)">
                  {{ $t('students.reroll') }}
                </button>
                <button type="button" class="text-slate-600 underline" :disabled="busy" @click="remove(student.account)">
                  {{ $t('students.remove') }}
                </button>
              </template>
            </td>
          </tr>
        </tbody>
      </table>

      <p v-if="anyRefused" data-test="refused-hint" class="max-w-2xl text-sm text-red-800">
        {{ $t('students.refusedHint') }}
      </p>
      <div v-if="anyCreating" class="flex max-w-2xl items-center gap-4 text-sm text-slate-600">
        <span>{{ $t('students.pendingHint') }}</span>
        <button type="button" class="text-emerald-700 underline" @click="load">{{ $t('students.reload') }}</button>
      </div>

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

      <form
        class="max-w-2xl space-y-3 rounded border border-slate-200 bg-white p-5"
        novalidate
        @submit.prevent="roll"
      >
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
        <p v-if="invalidCount" data-test="invalid" class="text-sm text-red-800">{{ $t('students.invalidCount') }}</p>
      </form>
    </template>
  </section>
</template>
