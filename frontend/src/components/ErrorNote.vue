<script setup>
defineProps({
  /** Code of the failure, see api/client.js. */
  code: { type: String, required: true },
})
</script>

<template>
  <div role="alert" class="rounded border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-900">
    <p class="font-semibold">{{ $t('errors.title') }}</p>
    <p>{{ $t(`errors.${code}`) }}</p>
  </div>
</template>
