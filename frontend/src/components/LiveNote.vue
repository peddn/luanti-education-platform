<script setup>
defineProps({
  /** False while the connection that reports changes is lost. */
  live: { type: Boolean, required: true },
})
</script>

<template>
  <p v-if="!live" data-test="offline" role="status" class="text-sm text-amber-700">{{ $t('live.offline') }}</p>
</template>
