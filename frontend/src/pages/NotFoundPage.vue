<script setup>
import { RouterLink } from 'vue-router'
</script>

<template>
  <section class="space-y-3">
    <h1 class="text-2xl font-bold">{{ $t('notFound.title') }}</h1>
    <p class="text-slate-600">{{ $t('notFound.text') }}</p>
    <RouterLink :to="{ name: 'overview' }" class="text-emerald-700 underline">{{ $t('notFound.home') }}</RouterLink>
  </section>
</template>
