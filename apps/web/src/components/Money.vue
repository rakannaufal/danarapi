<script setup lang="ts">
import { money } from '../domain.ts';
import { state } from '../store.ts';
defineProps<{ amount: string | bigint; prefix?: string }>();
</script>
<template><span class="money" :aria-label="state.hideAmounts ? 'Nominal disembunyikan' : `${prefix ?? ''}${money(amount)}`">{{ state.hideAmounts ? 'Rp••••••' : `${prefix ?? ''}${money(amount)}` }}</span></template>
