<script setup>
import { computed, onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'

import { api, errorCode } from '@/api/client'
import ErrorNote from '@/components/ErrorNote.vue'

/** @typedef {import('@/api/client').Group} Group */
/** @typedef {import('@/api/client').GroupProgress} GroupProgress */
/** @typedef {import('@/api/client').ModuleProgress} ModuleProgress */
/** @typedef {import('@/api/client').ProgressChange} ProgressChange */
/** @typedef {import('@/api/client').ErrorCode} ErrorCode */

const props = defineProps({
  /** Identifier of the group, from the address. */
  id: { type: String, required: true },
})

const group = ref(/** @type {Group | null} */ (null))
const progress = ref(/** @type {GroupProgress | null} */ (null))
const loadError = ref(/** @type {ErrorCode | null} */ (null))
const busy = ref(false)
const error = ref(/** @type {ErrorCode | null} */ (null))

// The cell that is open: one student in one module.
const open = ref(/** @type {{ account: string, module: string } | null} */ (null))
// The level chosen in the open cell, not ordered yet.
const wantedLevel = ref(1)

const anyPending = computed(
  () =>
    progress.value?.students.some((student) => student.modules.some((cell) => cell.change === 'pending')) ?? false,
)

/** The module the open cell belongs to. */
const openModule = computed(() => progress.value?.modules.find((module) => module.id === open.value?.module) ?? null)

/** The open cell with what the backend knows now. */
const openCell = computed(() => {
  const student = progress.value?.students.find((entry) => entry.account === open.value?.account)
  return student?.modules.find((cell) => cell.module === open.value?.module) ?? null
})

async function load() {
  busy.value = true
  try {
    group.value = await api.group(props.id)
    progress.value = await api.progress(props.id)
    loadError.value = null
  } catch (err) {
    loadError.value = errorCode(err)
  } finally {
    busy.value = false
  }
}

onMounted(load)

/**
 * @param {string} account
 * @param {ModuleProgress} cell
 */
function toggle(account, cell) {
  if (isOpen(account, cell.module)) {
    open.value = null
    return
  }
  open.value = { account, module: cell.module }
  wantedLevel.value = cell.level
  error.value = null
}

/**
 * @param {string} account
 * @param {string} module
 */
function isOpen(account, module) {
  return open.value?.account === account && open.value?.module === module
}

function orderLevel() {
  // The level the student is on needs no order, however the form was sent.
  if (openCell.value && wantedLevel.value !== openCell.value.level) {
    order({ level: wantedLevel.value })
  }
}

/**
 * Orders a change from the world and shows what the backend answers:
 * the old state, with the change on its way.
 *
 * @param {ProgressChange} change
 */
async function order(change) {
  if (!open.value) {
    return
  }
  busy.value = true
  error.value = null
  try {
    progress.value = await api.changeProgress(props.id, open.value.account, open.value.module, change)
  } catch (err) {
    error.value = errorCode(err)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <section class="space-y-6">
    <RouterLink :to="{ name: 'group', params: { id } }" class="text-sm text-emerald-700 underline">
      {{ $t('progress.back') }}
    </RouterLink>

    <ErrorNote v-if="loadError" :code="loadError" />
    <p v-else-if="!group || !progress" class="text-slate-500">{{ $t('progress.loading') }}</p>

    <template v-else>
      <div>
        <h1 class="text-2xl font-bold">{{ $t('progress.titleFor', { group: group.name }) }}</h1>
        <p class="mt-1 max-w-3xl text-slate-600">{{ $t('progress.intro') }}</p>
      </div>

      <div class="flex items-center gap-4 text-sm">
        <button
          type="button"
          data-test="reload"
          class="rounded border border-emerald-700 px-3 py-1.5 font-semibold text-emerald-800 hover:bg-emerald-50 disabled:opacity-50"
          :disabled="busy"
          @click="load"
        >
          {{ $t('progress.reload') }}
        </button>
        <span v-if="anyPending" data-test="pending-hint" class="text-amber-700">{{ $t('progress.pendingHint') }}</span>
      </div>

      <ErrorNote v-if="error" :code="error" />

      <p v-if="progress.modules.length === 0" data-test="no-modules" class="text-slate-500">
        {{ $t('progress.noModules') }}
      </p>
      <p v-else-if="progress.students.length === 0" data-test="no-students" class="text-slate-500">
        {{ $t('progress.noStudents') }}
      </p>
      <table v-else class="w-full border-collapse rounded border border-slate-200 bg-white text-left">
        <thead class="border-b border-slate-200 text-sm text-slate-500">
          <tr>
            <th class="px-4 py-2 font-semibold">{{ $t('progress.account') }}</th>
            <th v-for="module in progress.modules" :key="module.id" class="px-4 py-2 font-semibold">
              {{ module.title }}
            </th>
            <th class="px-4 py-2 font-semibold">{{ $t('progress.trophies') }}</th>
          </tr>
        </thead>
        <tbody>
          <template v-for="student in progress.students" :key="student.account">
            <tr data-test="student" class="border-b border-slate-100 align-top">
              <td class="px-4 py-2 font-mono font-semibold">{{ student.account }}</td>
              <td v-for="(cell, index) in student.modules" :key="cell.module" class="px-4 py-2">
                <button
                  type="button"
                  data-test="cell"
                  class="rounded px-2 py-1 text-left hover:bg-emerald-50"
                  :class="isOpen(student.account, cell.module) ? 'bg-emerald-50 ring-1 ring-emerald-700' : ''"
                  :aria-expanded="isOpen(student.account, cell.module)"
                  @click="toggle(student.account, cell)"
                >
                  <span class="block font-semibold">
                    {{ $t('progress.level', { level: cell.level, levels: progress.modules[index].levels }) }}
                  </span>
                  <span class="block text-sm text-slate-600">
                    {{ cell.started ? $t('progress.percent', { percent: cell.percent }) : $t('progress.notStarted') }}
                  </span>
                  <span v-if="cell.completed" class="block text-sm text-emerald-800">{{ $t('progress.completed') }}</span>
                  <span v-if="cell.locked" data-test="locked" class="block text-sm text-slate-600">
                    {{ $t('progress.locked') }}
                  </span>
                  <span
                    v-if="cell.change"
                    data-test="change"
                    class="block text-sm"
                    :class="cell.change === 'refused' ? 'text-red-800' : 'text-amber-700'"
                  >
                    {{ $t(`progress.change.${cell.change}`) }}
                  </span>
                </button>
              </td>
              <td class="px-4 py-2 text-sm text-slate-600">
                <span v-if="student.trophies.length === 0">{{ $t('progress.noTrophies') }}</span>
                <ul v-else data-test="trophies">
                  <li v-for="(trophy, index) in student.trophies" :key="index">
                    {{ $t('progress.trophy', { title: trophy.title, material: $t(`progress.materials.${trophy.material}`) }) }}
                  </li>
                </ul>
              </td>
            </tr>
            <tr
              v-if="open && open.account === student.account && openCell && openModule"
              data-test="detail"
              class="border-b border-slate-200 bg-slate-50"
            >
              <td :colspan="progress.modules.length + 2" class="space-y-4 px-4 py-4">
                <h2 class="font-semibold">
                  {{ $t('progress.detailTitle', { account: student.account, module: openModule.title }) }}
                </h2>

                <div>
                  <h3 class="text-sm font-semibold text-slate-600">
                    {{ $t('progress.tasksOf', { level: openCell.level }) }}
                  </h3>
                  <p v-if="openCell.tasks.length === 0" class="text-sm text-slate-500">{{ $t('progress.noTasks') }}</p>
                  <ul v-else data-test="tasks" class="mt-1 list-inside list-disc text-sm">
                    <li v-for="(task, index) in openCell.tasks" :key="index">
                      {{ $t('progress.task', { title: task.title, solved: task.solved, required: task.required }) }}
                    </li>
                  </ul>
                </div>

                <form class="flex flex-wrap items-end gap-3" novalidate @submit.prevent="orderLevel">
                  <label class="space-y-1">
                    <span class="block text-sm text-slate-600">{{ $t('progress.newLevel') }}</span>
                    <select
                      v-model.number="wantedLevel"
                      name="level"
                      class="block rounded border border-slate-300 bg-white px-3 py-2"
                    >
                      <option v-for="level in openModule.levels" :key="level" :value="level">{{ level }}</option>
                    </select>
                  </label>
                  <button
                    type="submit"
                    data-test="set-level"
                    class="rounded bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800 disabled:opacity-50"
                    :disabled="busy || wantedLevel === openCell.level"
                  >
                    {{ $t('progress.setLevel') }}
                  </button>
                  <button
                    type="button"
                    data-test="set-locked"
                    class="rounded border border-emerald-700 px-4 py-2 text-sm font-semibold text-emerald-800 hover:bg-emerald-50 disabled:opacity-50"
                    :disabled="busy"
                    @click="order({ locked: !openCell.locked })"
                  >
                    {{ openCell.locked ? $t('progress.unlock') : $t('progress.lock') }}
                  </button>
                </form>
                <p class="max-w-3xl text-sm text-slate-500">{{ $t('progress.changeHint') }}</p>
              </td>
            </tr>
          </template>
        </tbody>
      </table>
    </template>
  </section>
</template>
