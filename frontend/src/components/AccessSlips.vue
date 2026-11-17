<script setup>
import { computed, ref } from 'vue'

/** @typedef {import('@/api/client').AccessSlip} AccessSlip */

const props = defineProps({
  /** The slips with the start passwords, shown this once. */
  slips: { type: Array, required: true },
  /** Where players reach the world, or nothing. */
  address: { type: String, default: '' },
})

defineEmits(['done'])

// The names of the children. They are typed or pasted here, shown on
// the printout and nowhere else: this text never leaves the browser.
const names = ref('')
const nameList = computed(() => names.value.split('\n').map((line) => line.trim()))
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
      <label class="block space-y-1">
        <span class="font-semibold">{{ $t('slips.namesTitle') }}</span>
        <textarea
          v-model="names"
          name="names"
          rows="5"
          autocomplete="off"
          class="block w-full rounded border border-slate-300 bg-white px-3 py-2 font-mono text-sm"
        ></textarea>
        <span class="block text-sm text-slate-500">{{ $t('slips.namesHint') }}</span>
      </label>
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
          <template v-if="nameList[index]">
            <dt class="text-slate-500">{{ $t('slips.for') }}</dt>
            <dd data-test="child">{{ nameList[index] }}</dd>
          </template>
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
