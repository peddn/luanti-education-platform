<script setup>
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'

import { api, errorCode } from '@/api/client'
import ErrorNote from '@/components/ErrorNote.vue'

/** @typedef {import('@/api/client').Removal} Removal */
/** @typedef {import('@/api/client').ErrorCode} ErrorCode */

const { locale } = useI18n()

const removals = ref(/** @type {Removal[] | null} */ (null))
const loadError = ref(/** @type {ErrorCode | null} */ (null))

onMounted(async () => {
  try {
    removals.value = await api.removals()
  } catch (err) {
    loadError.value = errorCode(err)
  }
})

/**
 * Writes a moment in the chosen language.
 *
 * @param {number} at seconds since 1970
 */
function moment(at) {
  return new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(at * 1000))
}
</script>

<template>
  <section class="space-y-6">
    <ErrorNote v-if="loadError" :code="loadError" />
    <p v-else-if="!removals" class="text-slate-500">{{ $t('removals.loading') }}</p>

    <template v-else>
      <div>
        <h1 class="text-2xl font-bold">{{ $t('removals.title') }}</h1>
        <p class="mt-1 max-w-3xl text-slate-600">{{ $t('removals.intro') }}</p>
      </div>

      <p v-if="removals.length === 0" data-test="empty" class="text-slate-500">{{ $t('removals.empty') }}</p>
      <table v-else class="w-full max-w-4xl border-collapse rounded border border-slate-200 bg-white text-left">
        <thead class="border-b border-slate-200 text-sm text-slate-500">
          <tr>
            <th class="px-4 py-2 font-semibold">{{ $t('removals.time') }}</th>
            <th class="px-4 py-2 font-semibold">{{ $t('removals.account') }}</th>
            <th class="px-4 py-2 font-semibold">{{ $t('removals.group') }}</th>
            <th class="px-4 py-2 font-semibold">{{ $t('removals.by') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="(removal, index) in removals"
            :key="index"
            data-test="removal"
            class="border-b border-slate-100 last:border-0"
          >
            <td class="px-4 py-2">{{ moment(removal.time) }}</td>
            <td class="px-4 py-2 font-mono font-semibold">{{ removal.account }}</td>
            <td class="px-4 py-2">{{ removal.group }}</td>
            <td class="px-4 py-2">
              <span v-if="removal.by" class="font-mono">{{ removal.by }}</span>
              <span v-else class="text-slate-500">{{ $t('removals.inWorld') }}</span>
            </td>
          </tr>
        </tbody>
      </table>
      <p class="max-w-3xl text-sm text-slate-500">{{ $t('removals.hint') }}</p>
    </template>
  </section>
</template>
