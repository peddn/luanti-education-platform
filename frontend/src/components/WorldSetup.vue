<script setup>
defineProps({
  /** How it stands with the world of a group, see the type WorldSetup. */
  state: { type: String, required: true },
})
</script>

<template>
  <span v-if="state === 'running'" data-test="world-state" class="font-semibold text-emerald-700">
    {{ $t('groups.setup.running') }}
  </span>
  <span v-else-if="state === 'stopped'" data-test="world-state" class="font-semibold text-amber-700">
    {{ $t('groups.setup.stopped') }}
  </span>
  <span v-else-if="state === 'pending'" data-test="world-state" class="font-semibold text-slate-600">
    {{ $t('groups.setup.pending') }}
  </span>
  <span v-else-if="state === 'refused'" data-test="world-state" class="font-semibold text-red-800">
    {{ $t('groups.setup.refused') }}
  </span>
  <span v-else data-test="world-state" class="text-slate-500">{{ $t('groups.setup.manual') }}</span>
</template>
