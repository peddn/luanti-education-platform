<script setup>
import { onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'

import { api, errorCode } from '@/api/client'
import ErrorNote from '@/components/ErrorNote.vue'
import LastSeen from '@/components/LastSeen.vue'
import { useAuthStore } from '@/stores/auth'

/** @typedef {import('@/api/client').Group} Group */
/** @typedef {import('@/api/client').ErrorCode} ErrorCode */

const auth = useAuthStore()

const groups = ref(/** @type {Group[] | null} */ (null))
const error = ref(/** @type {ErrorCode | null} */ (null))

onMounted(async () => {
  try {
    groups.value = await api.groups()
  } catch (err) {
    error.value = errorCode(err)
  }
})
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
          <td class="px-4 py-3 text-right">
            <RouterLink :to="{ name: 'group', params: { id: group.id } }" class="text-emerald-700 underline">
              {{ $t('groups.open') }}
            </RouterLink>
          </td>
        </tr>
      </tbody>
    </table>
  </section>
</template>
