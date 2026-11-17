<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

const props = defineProps({
  /** Seconds since 1970 (UTC), or nothing if the world never called. */
  at: { type: Number, default: undefined },
})

const { locale } = useI18n()

// The browser writes the time in the chosen language.
const time = computed(() =>
  props.at === undefined
    ? ''
    : new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium', timeStyle: 'short' }).format(
        new Date(props.at * 1000),
      ),
)
</script>

<template>
  <span v-if="at === undefined" class="text-amber-700">{{ $t('groups.neverSeen') }}</span>
  <span v-else>{{ $t('groups.lastSeen', { time }) }}</span>
</template>
