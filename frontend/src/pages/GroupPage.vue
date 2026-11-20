<script setup>
import { computed, onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'

import { api, errorCode } from '@/api/client'
import ErrorNote from '@/components/ErrorNote.vue'
import LastSeen from '@/components/LastSeen.vue'
import LiveNote from '@/components/LiveNote.vue'
import { useGroupChanges } from '@/composables/groupChanges'
import { useAuthStore } from '@/stores/auth'

/** @typedef {import('@/api/client').Group} Group */
/** @typedef {import('@/api/client').GroupChange} GroupChange */
/** @typedef {import('@/api/client').ErrorCode} ErrorCode */

const props = defineProps({
  /** Identifier of the group, from the address. */
  id: { type: String, required: true },
})

const auth = useAuthStore()
// What the page offers follows the role. The backend checks it again
// with every change.
const mayChange = computed(() => auth.me?.school_admin === true)

const group = ref(/** @type {Group | null} */ (null))
const candidates = ref(/** @type {string[]} */ ([]))
const loadError = ref(/** @type {ErrorCode | null} */ (null))

const name = ref('')
const address = ref('')
const chosen = ref(/** @type {string[]} */ ([]))
const saving = ref(false)
const saved = ref(false)
const invalidName = ref(false)
const saveError = ref(/** @type {ErrorCode | null} */ (null))

/** @param {Group} fresh */
function show(fresh) {
  group.value = fresh
  name.value = fresh.name
  address.value = fresh.address ?? ''
  chosen.value = [...fresh.teachers]
}

// Teachers who are assigned stay in the list, also if they lost their
// web access in the meantime.
const choices = computed(() => [...new Set([...candidates.value, ...(group.value?.teachers ?? [])])].sort())

onMounted(async () => {
  try {
    show(await api.group(props.id))
    if (mayChange.value) {
      candidates.value = await api.teachers()
    }
  } catch (err) {
    loadError.value = errorCode(err)
  }
})

// Loads the group again after the backend said it changed. A form that
// somebody is filling in is left alone.
async function refresh() {
  try {
    const fresh = await api.group(props.id)
    const old = group.value
    const untouched =
      old !== null &&
      name.value === old.name &&
      address.value === (old.address ?? '') &&
      [...chosen.value].sort().join() === [...old.teachers].sort().join()
    if (untouched && !saving.value) {
      show(fresh)
    } else {
      group.value = fresh
    }
  } catch (err) {
    if (errorCode(err) !== 'network') {
      loadError.value = errorCode(err)
    }
  }
}

const { live } = useGroupChanges(props.id, ['group'], refresh)

async function save() {
  saved.value = false
  saveError.value = null
  const wanted = name.value.trim()
  invalidName.value = wanted.length === 0 || [...wanted].length > 60
  if (invalidName.value || !group.value) {
    return
  }
  /** @type {GroupChange} */
  const change = { teachers: [...chosen.value].sort() }
  if (wanted !== group.value.name) {
    change.name = wanted
  }
  if (address.value.trim() !== (group.value.address ?? '')) {
    change.address = address.value.trim()
  }
  saving.value = true
  try {
    show(await api.changeGroup(props.id, change))
    saved.value = true
  } catch (err) {
    saveError.value = errorCode(err)
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <section class="max-w-2xl space-y-6">
    <RouterLink :to="{ name: 'groups' }" class="text-sm text-emerald-700 underline">{{ $t('groups.back') }}</RouterLink>

    <ErrorNote v-if="loadError" :code="loadError" />
    <p v-else-if="!group" class="text-slate-500">{{ $t('groups.loading') }}</p>

    <template v-else>
      <div>
        <h1 data-test="name" class="text-2xl font-bold">{{ group.name }}</h1>
        <p class="mt-1 text-sm text-slate-600"><LastSeen :at="group.last_seen_at ?? undefined" /></p>
      </div>
      <LiveNote :live="live" />

      <RouterLink
        :to="{ name: 'students', params: { id } }"
        data-test="students"
        class="inline-block rounded bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800"
      >
        {{ $t('groups.students') }}
      </RouterLink>
      <RouterLink
        :to="{ name: 'progress', params: { id } }"
        data-test="progress"
        class="ml-3 inline-block rounded border border-emerald-700 px-4 py-2 text-sm font-semibold text-emerald-800 hover:bg-emerald-50"
      >
        {{ $t('groups.progress') }}
      </RouterLink>
      <RouterLink
        :to="{ name: 'protocols', params: { id } }"
        data-test="protocols"
        class="ml-3 inline-block rounded border border-emerald-700 px-4 py-2 text-sm font-semibold text-emerald-800 hover:bg-emerald-50"
      >
        {{ $t('groups.protocols') }}
      </RouterLink>
      <RouterLink
        :to="{ name: 'rewards', params: { id } }"
        data-test="rewards"
        class="ml-3 inline-block rounded border border-emerald-700 px-4 py-2 text-sm font-semibold text-emerald-800 hover:bg-emerald-50"
      >
        {{ $t('groups.rewards') }}
      </RouterLink>

      <div v-if="!mayChange" class="space-y-3 rounded border border-slate-200 bg-white p-5">
        <h2 class="font-semibold">{{ $t('groups.teachers') }}</h2>
        <ul v-if="group.teachers.length" data-test="teachers" class="list-inside list-disc">
          <li v-for="teacher in group.teachers" :key="teacher">{{ teacher }}</li>
        </ul>
        <p v-else class="text-slate-400">{{ $t('groups.noTeachers') }}</p>
        <h2 class="font-semibold">{{ $t('groups.address') }}</h2>
        <p v-if="group.address" data-test="address">{{ group.address }}</p>
        <p v-else class="text-slate-400">{{ $t('groups.noAddress') }}</p>
        <p class="text-sm text-slate-500">{{ $t('groups.readOnly') }}</p>
      </div>

      <form v-else class="space-y-6 rounded border border-slate-200 bg-white p-5" novalidate @submit.prevent="save">
        <label class="block space-y-1">
          <span class="font-semibold">{{ $t('groups.newName') }}</span>
          <input
            v-model="name"
            type="text"
            name="name"
            maxlength="60"
            class="block w-full rounded border border-slate-300 bg-white px-3 py-2"
            :aria-invalid="invalidName"
          />
        </label>
        <p v-if="invalidName" data-test="invalid" class="text-sm text-red-800">{{ $t('groups.invalidName') }}</p>

        <label class="block space-y-1">
          <span class="font-semibold">{{ $t('groups.address') }}</span>
          <input
            v-model="address"
            type="text"
            name="address"
            maxlength="100"
            class="block w-full rounded border border-slate-300 bg-white px-3 py-2"
          />
          <span class="block text-sm text-slate-500">{{ $t('groups.addressHint') }}</span>
        </label>

        <fieldset class="space-y-2">
          <legend class="font-semibold">{{ $t('groups.assign') }}</legend>
          <p class="text-sm text-slate-500">{{ $t('groups.assignHint') }}</p>
          <p v-if="choices.length === 0" class="text-slate-400">{{ $t('groups.noCandidates') }}</p>
          <label v-for="teacher in choices" :key="teacher" class="flex items-center gap-2">
            <input v-model="chosen" type="checkbox" :value="teacher" class="h-4 w-4" />
            <span>{{ teacher }}</span>
          </label>
        </fieldset>

        <ErrorNote v-if="saveError" :code="saveError" />
        <div class="flex items-center gap-4">
          <button
            type="submit"
            class="rounded bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800 disabled:opacity-50"
            :disabled="saving"
          >
            {{ saving ? $t('groups.saving') : $t('groups.save') }}
          </button>
          <span v-if="saved" data-test="saved" role="status" class="text-sm text-emerald-800">{{ $t('groups.saved') }}</span>
        </div>
      </form>
    </template>
  </section>
</template>
