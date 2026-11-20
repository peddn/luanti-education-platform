<script setup>
import { computed, onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'

import { api, errorCode } from '@/api/client'
import ErrorNote from '@/components/ErrorNote.vue'
import LiveNote from '@/components/LiveNote.vue'
import { useGroupChanges } from '@/composables/groupChanges'

/** @typedef {import('@/api/client').Group} Group */
/** @typedef {import('@/api/client').GroupRewards} GroupRewards */
/** @typedef {import('@/api/client').RewardTable} RewardTable */
/** @typedef {import('@/api/client').ErrorCode} ErrorCode */
/** @typedef {'task' | 'daily' | 'level' | 'stage' | 'module'} Occasion */

const props = defineProps({
  /** Identifier of the group, from the address. */
  id: { type: String, required: true },
})

/** The rows of the table, in the order they are shown. */
const OCCASIONS = /** @type {Occasion[]} */ (['task', 'daily', 'level', 'stage', 'module'])

const group = ref(/** @type {Group | null} */ (null))
const rewards = ref(/** @type {GroupRewards | null} */ (null))
const loadError = ref(/** @type {ErrorCode | null} */ (null))
const busy = ref(false)
const error = ref(/** @type {ErrorCode | null} */ (null))

// What is being typed, not ordered yet. Kept apart from what the world
// reported, so an update from the backend does not wipe it.
const draft = ref(/** @type {RewardTable | null} */ (null))
// True after the first click on putting the default back.
const resetting = ref(false)

/** @param {RewardTable} table */
function copy(table) {
  return /** @type {RewardTable} */ (JSON.parse(JSON.stringify(table)))
}

const dirty = computed(
  () => draft.value !== null && JSON.stringify(draft.value) !== JSON.stringify(rewards.value?.table ?? null),
)
const pending = computed(() => rewards.value?.change === 'pending')

const valid = computed(() => {
  const table = draft.value
  const limits = rewards.value
  if (!table || !limits) {
    return false
  }
  const whole = (/** @type {unknown} */ value, /** @type {number} */ min, /** @type {number} */ max) =>
    typeof value === 'number' && Number.isInteger(value) && value >= min && value <= max
  return (
    OCCASIONS.every((occasion) => whole(table[occasion].count, 1, limits.max_count)) &&
    whole(table.daily_limit, 0, limits.max_daily_limit)
  )
})

/**
 * Takes what the backend says. The draft follows unless something was
 * typed that is not ordered yet.
 *
 * @param {GroupRewards} answer
 * @param {boolean} [force] true to drop what was typed
 */
function take(answer, force = false) {
  const keep = dirty.value && !force
  rewards.value = answer
  if (!keep) {
    draft.value = answer.table ? copy(answer.table) : null
  }
}

async function load() {
  busy.value = true
  try {
    group.value = await api.group(props.id)
    take(await api.rewards(props.id), true)
    loadError.value = null
  } catch (err) {
    loadError.value = errorCode(err)
  } finally {
    busy.value = false
  }
}

onMounted(load)

// The world reports its table after every change, and the backend says
// so. A lost connection leaves the page as it is.
async function refresh() {
  try {
    take(await api.rewards(props.id), pending.value)
  } catch (err) {
    if (errorCode(err) !== 'network') {
      loadError.value = errorCode(err)
    }
  }
}

const { live } = useGroupChanges(props.id, ['group'], refresh)

/**
 * The items of the select for one row: what can be chosen, and what the
 * row holds if that is no longer on the list.
 *
 * @param {Occasion} occasion
 */
function choicesFor(occasion) {
  const list = rewards.value?.choices ?? []
  const current = draft.value?.[occasion].name
  if (current && !list.some((choice) => choice.name === current)) {
    return [...list, { name: current, title: current }]
  }
  return list
}

/** @param {RewardTable} [table] the table to order, or nothing for the default */
async function order(table) {
  busy.value = true
  error.value = null
  try {
    take(await api.changeRewards(props.id, table), true)
    resetting.value = false
  } catch (err) {
    error.value = errorCode(err)
  } finally {
    busy.value = false
  }
}

function save() {
  if (draft.value && valid.value && dirty.value) {
    order(copy(draft.value))
  }
}

function discard() {
  if (rewards.value) {
    take(rewards.value, true)
  }
}
</script>

<template>
  <section class="space-y-6">
    <RouterLink :to="{ name: 'group', params: { id } }" class="text-sm text-emerald-700 underline">
      {{ $t('rewards.back') }}
    </RouterLink>

    <ErrorNote v-if="loadError" :code="loadError" />
    <p v-else-if="!group || !rewards" class="text-slate-500">{{ $t('rewards.loading') }}</p>

    <template v-else>
      <div>
        <h1 class="text-2xl font-bold">{{ $t('rewards.title', { name: group.name }) }}</h1>
        <p class="mt-1 max-w-3xl text-slate-600">{{ $t('rewards.intro') }}</p>
      </div>
      <LiveNote :live="live" />

      <ErrorNote v-if="error" :code="error" />

      <p v-if="!draft" data-test="not-reported" class="text-slate-500">{{ $t('rewards.notReported') }}</p>

      <form v-else class="max-w-3xl space-y-5" novalidate @submit.prevent="save">
        <p v-if="pending" data-test="change" class="text-amber-700">{{ $t('progress.change.pending') }}</p>
        <p v-else-if="rewards.change === 'refused'" data-test="change" class="text-red-800">
          {{ $t('rewards.refused') }}
        </p>

        <table class="w-full border-collapse rounded border border-slate-200 bg-white text-left">
          <thead class="border-b border-slate-200 text-sm text-slate-500">
            <tr>
              <th class="px-4 py-2 font-semibold">{{ $t('rewards.occasion') }}</th>
              <th class="px-4 py-2 font-semibold">{{ $t('rewards.item') }}</th>
              <th class="px-4 py-2 font-semibold">{{ $t('rewards.count') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="occasion in OCCASIONS"
              :key="occasion"
              data-test="row"
              class="border-b border-slate-100 align-top last:border-0"
            >
              <td class="px-4 py-3">
                <span class="block font-semibold">{{ $t(`rewards.occasions.${occasion}`) }}</span>
                <span class="block text-sm text-slate-500">{{ $t(`rewards.hints.${occasion}`) }}</span>
              </td>
              <td class="px-4 py-3">
                <select
                  v-model="draft[occasion].name"
                  :name="`item-${occasion}`"
                  :aria-label="$t('rewards.item')"
                  class="rounded border border-slate-300 bg-white px-3 py-2"
                  :disabled="busy || pending"
                >
                  <option v-for="choice in choicesFor(occasion)" :key="choice.name" :value="choice.name">
                    {{ choice.title }}
                  </option>
                </select>
              </td>
              <td class="px-4 py-3">
                <input
                  v-model.number="draft[occasion].count"
                  type="number"
                  min="1"
                  :max="rewards.max_count"
                  :name="`count-${occasion}`"
                  :aria-label="$t('rewards.count')"
                  class="w-24 rounded border border-slate-300 px-3 py-2"
                  :disabled="busy || pending"
                />
              </td>
            </tr>
          </tbody>
        </table>
        <p class="text-sm text-slate-500">{{ $t('rewards.effortHint') }}</p>

        <label class="block space-y-1">
          <span class="block font-semibold">{{ $t('rewards.dailyLimit') }}</span>
          <span class="block text-sm text-slate-500">
            {{ $t('rewards.dailyLimitHint', { max: rewards.max_daily_limit }) }}
          </span>
          <input
            v-model.number="draft.daily_limit"
            type="number"
            min="0"
            :max="rewards.max_daily_limit"
            name="daily-limit"
            class="w-24 rounded border border-slate-300 px-3 py-2"
            :disabled="busy || pending"
          />
        </label>

        <p v-if="!valid" data-test="invalid" class="text-sm text-red-800">
          {{ $t('rewards.invalid', { max: rewards.max_count, limit: rewards.max_daily_limit }) }}
        </p>

        <div class="flex flex-wrap items-center gap-3">
          <button
            type="submit"
            data-test="save"
            class="rounded bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800 disabled:opacity-40"
            :disabled="busy || pending || !dirty || !valid"
          >
            {{ $t('rewards.save') }}
          </button>
          <button
            v-if="dirty"
            type="button"
            data-test="discard"
            class="text-sm text-slate-600 underline"
            :disabled="busy"
            @click="discard"
          >
            {{ $t('rewards.discard') }}
          </button>
          <span class="grow"></span>
          <template v-if="resetting">
            <span class="text-sm text-slate-600">{{ $t('rewards.resetConfirm') }}</span>
            <button
              type="button"
              data-test="reset-yes"
              class="text-sm font-semibold text-red-800 underline"
              :disabled="busy"
              @click="order()"
            >
              {{ $t('rewards.resetYes') }}
            </button>
            <button type="button" class="text-sm text-slate-600 underline" @click="resetting = false">
              {{ $t('students.resetNo') }}
            </button>
          </template>
          <button
            v-else
            type="button"
            data-test="reset"
            class="text-sm text-emerald-700 underline"
            :disabled="busy || pending"
            @click="resetting = true"
          >
            {{ $t('rewards.reset') }}
          </button>
        </div>
        <p class="text-sm text-slate-500">{{ $t('rewards.fromNow') }}</p>
      </form>
    </template>
  </section>
</template>
