<script setup lang="ts">
import { computed } from 'vue';
import Money from './Money.vue';
const props = defineProps<{ title: string; rows: { id: string; name: string; amount: string }[] }>();
const colors = ['#0066cc', '#32846b', '#9471b4', '#c49a22', '#c26268', '#698397', '#857154'];
const total = computed(() => props.rows.reduce((sum, row) => sum + BigInt(row.amount), 0n));
const segments = computed(() => {
  let offset = 0;
  return props.rows.filter(row => BigInt(row.amount) > 0n).map((row, index) => {
    const fraction = total.value > 0n ? Number(BigInt(row.amount) * 1000000n / total.value) / 1000000 : 0;
    const segment = { ...row, color: colors[index % colors.length], length: fraction * 251.327, offset: -offset, percent: fraction * 100 };
    offset += segment.length;
    return segment;
  });
});
</script>
<template>
  <section class="card donut-card">
    <h2>{{ title }}</h2>
    <div class="donut-layout">
      <div class="donut-visual"><svg viewBox="0 0 110 110" role="img" :aria-label="`Diagram ${title}`"><circle cx="55" cy="55" r="40" fill="none" stroke="var(--line)" stroke-width="13" /><circle v-for="row in segments" :key="row.id" cx="55" cy="55" r="40" fill="none" :stroke="row.color" stroke-width="13" :stroke-dasharray="`${row.length} ${251.327 - row.length}`" :stroke-dashoffset="row.offset" transform="rotate(-90 55 55)" /></svg><div class="donut-center"><span>Total</span><strong><Money :amount="total" /></strong></div></div>
      <div v-if="segments.length" class="donut-legend"><div v-for="row in segments" :key="row.id" class="donut-legend-row"><span class="chart-dot" :style="{ background: row.color }"></span><span>{{ row.name }}<small>{{ row.percent.toLocaleString('id-ID', { maximumFractionDigits: 1 }) }}%</small></span><Money :amount="row.amount" /></div></div><p v-else class="muted">Belum ada transaksi pada periode ini.</p>
    </div>
  </section>
</template>
