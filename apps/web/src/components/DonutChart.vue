<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import Money from './Money.vue';
import Icon from './Icon.vue';
import { chartColor, chartPercent } from '../report-charts.ts';
const props = defineProps<{ title: string; rows: { id: string; name: string; amount: string; color?: string }[]; showZeroRows?: boolean }>();
const selectedID = ref('');
const hoveredID = ref('');
const total = computed(() => props.rows.reduce((sum, row) => sum + (BigInt(row.amount) > 0n ? BigInt(row.amount) : 0n), 0n));
const segments = computed(() => {
  let offset = 0;
  return props.rows.filter(row => props.showZeroRows || BigInt(row.amount) > 0n).map(row => {
    const percent = chartPercent(row.amount, total.value);
    const segment = { ...row, color: row.color ?? chartColor(row.id), length: percent / 100 * 251.327, offset: -offset, percent };
    offset += segment.length;
    return segment;
  });
});
const selected = computed(() => segments.value.find(row => row.id === (hoveredID.value || selectedID.value)));
watch(segments, rows => {
  if (!rows.some(row => row.id === selectedID.value)) selectedID.value = '';
  hoveredID.value = '';
});
function select(identifier: string) { selectedID.value = selectedID.value === identifier ? '' : identifier; }
</script>
<template>
  <section class="card donut-card">
    <div class="section-heading"><h2>{{ title }}</h2><Icon name="budget" :size="19" /></div>
    <div class="donut-layout">
      <div class="donut-visual">
        <svg viewBox="0 0 110 110" role="group" :aria-label="`Diagram ${title}`" @pointerleave="hoveredID = ''">
          <circle cx="55" cy="55" r="40" fill="none" stroke="var(--chart-track)" stroke-width="12" />
          <circle v-for="row in segments.filter(segment => segment.length > 0)" :key="row.id" class="chart-segment" role="button" tabindex="0" :aria-label="`${row.name}, ${row.percent.toLocaleString('id-ID', { maximumFractionDigits: 1 })}%`" :aria-pressed="selectedID === row.id" cx="55" cy="55" r="40" fill="none" :stroke="row.color" :stroke-width="selected?.id === row.id ? 15 : 12" :stroke-dasharray="`${row.length} ${251.327 - row.length}`" :stroke-dashoffset="row.offset" transform="rotate(-90 55 55)" :opacity="selected && selected.id !== row.id ? 0.25 : 1" @pointerenter="hoveredID = row.id" @focus="hoveredID = row.id" @blur="hoveredID = ''" @click="select(row.id)" @keydown.enter.prevent="select(row.id)" @keydown.space.prevent="select(row.id)" />
        </svg>
        <div class="donut-center"><span>{{ selected?.name ?? 'Total' }}</span><strong><Money :amount="selected?.amount ?? total" /></strong></div>
      </div>
      <div v-if="segments.length" class="donut-legend">
        <button v-for="row in segments" :key="row.id" class="donut-legend-row" :aria-pressed="selectedID === row.id" @click="select(row.id)"><span class="chart-dot" :style="{ background: row.color }"></span><span class="donut-label">{{ row.name }}<small>{{ row.percent.toLocaleString('id-ID', { maximumFractionDigits: 1 }) }}%</small></span><Money :amount="row.amount" /></button>
      </div>
      <div v-else class="chart-empty"><Icon name="budget" :size="22" /><span>Belum ada alokasi</span></div>
    </div>
    <div v-if="selected" class="chart-inspector" role="status" :aria-label="`Rincian ${title}`"><span class="chart-dot" :style="{ background: selected.color }"></span><span><strong>{{ selected.name }}</strong><small>{{ selected.percent.toLocaleString('id-ID', { maximumFractionDigits: 1 }) }}% dari total</small></span><Money :amount="selected.amount" /></div>
  </section>
</template>
