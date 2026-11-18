<script setup>
import { computed, ref } from 'vue'

/** @typedef {import('@/api/client').AccessSlip} AccessSlip */

const props = defineProps({
  /** The slips with the start passwords, shown this once. */
  slips: { type: Array, required: true },
  /** Where players reach the world, or nothing. */
  address: { type: String, default: '' },
  /** True if the slips carry a new password for accounts that exist. */
  reset: { type: Boolean, default: false },
})

defineEmits(['done'])

// The names of the children, one per slip. They are typed here, shown
// on the printout and nowhere else: they never leave the browser.
const names = ref(/** @type {string[]} */ ([]))
const list = computed(() => /** @type {AccessSlip[]} */ (props.slips))

function print() {
  window.print()
}
</script>

<template>
  <section class="space-y-6">
    <div class="space-y-4 print:hidden">
      <h2 class="text-xl font-bold">{{ $t('slips.title') }}</h2>
      <p role="alert" class="rounded border border-amber-300 bg-amber-50 px-4 py-3 text-amber-900">
        {{ $t('slips.once') }}
      </p>
      <p v-if="reset" data-test="reset-note" class="text-sm text-slate-600">{{ $t('slips.resetNote') }}</p>
      <p class="text-sm text-slate-600">{{ $t('slips.namesHint') }}</p>
      <div class="flex flex-wrap items-center gap-4">
        <button
          type="button"
          data-test="print"
          class="rounded bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800"
          @click="print"
        >
          {{ $t('slips.print') }}
        </button>
        <button
          type="button"
          data-test="done"
          class="rounded border border-slate-300 px-4 py-2 text-sm text-slate-700 hover:bg-slate-100"
          :title="$t('slips.confirmLeave')"
          @click="$emit('done')"
        >
          {{ $t('slips.done') }}
        </button>
      </div>
    </div>

    <div class="grid gap-4 sm:grid-cols-2 print:grid-cols-2 print:gap-0">
      <article
        v-for="(slip, index) in list"
        :key="slip.account"
        data-test="slip"
        class="break-inside-avoid space-y-2 rounded border border-slate-300 bg-white p-4 print:rounded-none print:border-dashed"
      >
        <h3 class="font-bold">{{ $t('slips.heading') }}</h3>
        <dl class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
          <dt class="text-slate-500" :class="{ 'print:hidden': !names[index]?.trim() }">{{ $t('slips.for') }}</dt>
          <dd :class="{ 'print:hidden': !names[index]?.trim() }">
            <input
              v-model="names[index]"
              type="text"
              :name="`child-${index}`"
              autocomplete="off"
              :placeholder="$t('slips.namePlaceholder')"
              :aria-label="$t('slips.for')"
              class="w-full rounded border border-slate-300 bg-white px-2 py-1 print:hidden"
            />
            <span data-test="child" class="hidden print:inline">{{ names[index]?.trim() }}</span>
          </dd>
          <dt class="text-slate-500">{{ $t('slips.address') }}</dt>
          <dd data-test="address">{{ address || $t('slips.noAddress') }}</dd>
          <dt class="text-slate-500">{{ $t('slips.account') }}</dt>
          <dd data-test="account" class="font-mono text-lg font-semibold">{{ slip.account }}</dd>
          <dt class="text-slate-500">{{ $t('slips.password') }}</dt>
          <dd data-test="password" class="font-mono text-lg font-semibold">{{ slip.password }}</dd>
        </dl>
        <p class="text-xs text-slate-500">{{ $t('slips.hint') }}</p>
      </article>
    </div>
  </section>
</template>
