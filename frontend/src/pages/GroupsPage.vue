<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { RouterLink } from 'vue-router'

import { api, errorCode } from '@/api/client'
import ErrorNote from '@/components/ErrorNote.vue'
import LastSeen from '@/components/LastSeen.vue'
import WorldSetup from '@/components/WorldSetup.vue'
import { useAuthStore } from '@/stores/auth'

/** @typedef {import('@/api/client').Group} Group */
/** @typedef {import('@/api/client').ErrorCode} ErrorCode */

const auth = useAuthStore()

const groups = ref(/** @type {Group[] | null} */ (null))
const error = ref(/** @type {ErrorCode | null} */ (null))

const mayCreate = computed(() => auth.me?.school_admin === true)
const newName = ref('')
const creating = ref(false)
const invalidName = ref(false)
const createError = ref(/** @type {ErrorCode | null} */ (null))

async function load() {
  try {
    groups.value = await api.groups()
    error.value = null
  } catch (err) {
    // A page that shows groups keeps them while the backend is away.
    if (groups.value === null || errorCode(err) !== 'network') {
      error.value = errorCode(err)
    }
  }
}

// While a world is being set up, the list is asked again and again, so
// the page shows by itself when the world runs.
const WATCH_MS = 3000
/** @type {ReturnType<typeof setInterval> | undefined} */
let watching
function watch() {
  const pending = groups.value?.some((group) => group.world === 'pending') ?? false
  if (pending && watching === undefined) {
    watching = setInterval(async () => {
      await load()
      watch()
    }, WATCH_MS)
  } else if (!pending && watching !== undefined) {
    clearInterval(watching)
    watching = undefined
  }
}

onMounted(async () => {
  await load()
  watch()
})
onUnmounted(() => clearInterval(watching))

async function create() {
  createError.value = null
  const wanted = newName.value.trim()
  invalidName.value = wanted.length === 0 || [...wanted].length > 60
  if (invalidName.value) {
    return
  }
  creating.value = true
  try {
    await api.createGroup(wanted)
    newName.value = ''
    await load()
    watch()
  } catch (err) {
    createError.value = errorCode(err)
  } finally {
    creating.value = false
  }
}
</script>

<template>
  <section class="space-y-6">
    <div>
      <h1 class="text-2xl font-bold">{{ $t('groups.title') }}</h1>
      <p class="mt-1 text-slate-600">
        {{ auth.me?.school_admin ? $t('groups.introAdmin') : $t('groups.introTeacher') }}
      </p>
    </div>

    <ErrorNote v-if="error" :code="error" />
    <p v-else-if="!groups" class="text-slate-500">{{ $t('groups.loading') }}</p>
    <p v-else-if="groups.length === 0" data-test="empty" class="rounded border border-slate-200 bg-white p-5">
      {{ auth.me?.school_admin ? $t('groups.emptyAdmin') : $t('groups.emptyTeacher') }}
    </p>

    <table v-else class="w-full border-collapse rounded border border-slate-200 bg-white text-left">
      <thead class="border-b border-slate-200 text-sm text-slate-500">
        <tr>
          <th class="px-4 py-2 font-semibold">{{ $t('groups.name') }}</th>
          <th class="px-4 py-2 font-semibold">{{ $t('groups.teachers') }}</th>
          <th class="px-4 py-2 font-semibold">{{ $t('groups.world') }}</th>
          <th class="px-4 py-2 font-semibold">{{ $t('groups.state') }}</th>
          <th class="px-4 py-2"></th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="group in groups" :key="group.id" data-test="group" class="border-b border-slate-100 last:border-0">
          <td class="px-4 py-3 font-semibold">{{ group.name }}</td>
          <td class="px-4 py-3">
            <span v-if="group.teachers.length">{{ group.teachers.join(', ') }}</span>
            <span v-else class="text-slate-400">{{ $t('groups.noTeachers') }}</span>
          </td>
          <td class="px-4 py-3 text-sm text-slate-600"><LastSeen :at="group.last_seen_at ?? undefined" /></td>
          <td class="px-4 py-3 text-sm"><WorldSetup :state="group.world" /></td>
          <td class="px-4 py-3 text-right">
            <RouterLink :to="{ name: 'group', params: { id: group.id } }" class="text-emerald-700 underline">
              {{ $t('groups.open') }}
            </RouterLink>
          </td>
        </tr>
      </tbody>
    </table>

    <form
      v-if="mayCreate && groups"
      data-test="create"
      class="max-w-2xl space-y-3 rounded border border-slate-200 bg-white p-5"
      novalidate
      @submit.prevent="create"
    >
      <h2 class="font-semibold">{{ $t('groups.create') }}</h2>
      <p class="text-sm text-slate-500">{{ $t('groups.createHint') }}</p>
      <label class="block space-y-1">
        <span class="font-semibold">{{ $t('groups.createName') }}</span>
        <input
          v-model="newName"
          type="text"
          name="new-name"
          maxlength="60"
          class="block w-full rounded border border-slate-300 bg-white px-3 py-2"
          :aria-invalid="invalidName"
        />
      </label>
      <p v-if="invalidName" data-test="invalid" class="text-sm text-red-800">{{ $t('groups.invalidName') }}</p>
      <ErrorNote v-if="createError" :code="createError" />
      <button
        type="submit"
        :disabled="creating"
        class="rounded bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800 disabled:opacity-60"
      >
        {{ creating ? $t('groups.creating') : $t('groups.createButton') }}
      </button>
    </form>
  </section>
</template>
