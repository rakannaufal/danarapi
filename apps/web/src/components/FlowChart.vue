<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { state } from '../store.ts';
import { chartAxisLabel, chartPercent } from '../report-charts.ts';
import Money from './Money.vue';
import Icon from './Icon.vue';
const props = defineProps<{ rows: { month: string; personalIncome: string; personalExpense: string }[]; yearly?: boolean }>();
const selectedKey = ref(''), hoveredKey = ref('');
function select(key: string) { selectedKey.value = selectedKey.value === key ? '' : key; }
const maximum = computed(() => props.rows.reduce((highest, row) => [BigInt(row.personalIncome), BigInt(row.personalExpense)].reduce((largest, amount) => amount > largest ? amount : largest, highest), 0n));
const ticks = computed(() => Array.from({ length: 5 }, (_, index) => ({ amount: maximum.value * BigInt(4 - index) / 4n, position: index * 43 })));
const series = computed(() => props.rows.map((row, index) => {
  const center = (index + 0.5) * 610 / Math.max(props.rows.length, 1);
  const income = chartPercent(row.personalIncome, maximum.value) / 100 * 172;
  const expense = chartPercent(row.personalExpense, maximum.value) / 100 * 172;
  return { ...row, center, income, expense, bars: [{ kind: 'income', name: 'Pemasukan', height: income, x: center - 33 }, { kind: 'expense', name: 'Pengeluaran', height: expense, x: center + 5 }].filter(bar => bar.height > 0), label: props.yearly ? row.month : new Intl.DateTimeFormat('id-ID', { month: 'short', year: '2-digit', timeZone: 'UTC' }).format(new Date(`${row.month}-01T00:00:00Z`)) };
}));
const selected = computed(() => {
  const key = hoveredKey.value || selectedKey.value;
  for (const row of series.value) {
    if (key === `${row.month}:income`) return { label: `Pemasukan · ${row.label}`, amount: row.personalIncome, color: 'var(--chart-income)' };
    if (key === `${row.month}:expense`) return { label: `Pengeluaran · ${row.label}`, amount: row.personalExpense, color: 'var(--chart-expense)' };
  }
  return undefined;
});
watch(series, () => { selectedKey.value = ''; hoveredKey.value = ''; });
</script>
<template>
  <section class="card flow-card">
    <div class="section-heading"><div><h2>Arus keuangan</h2><p class="muted">{{ yearly ? 'Perbandingan tiga tahun' : 'Perbandingan tiga bulan' }}</p></div><span class="report-legend"><span><i class="chart-dot chart-income"></i>Pemasukan</span><span><i class="chart-dot chart-expense"></i>Pengeluaran</span></span></div>
    <div v-if="maximum > 0n" class="flow-plot">
      <div class="flow-axis" aria-hidden="true"><span v-for="tick in ticks" :key="tick.position">{{ chartAxisLabel(tick.amount, state.hideAmounts) }}</span></div>
      <div class="flow-bars">
        <svg class="flow-chart" viewBox="0 0 610 172" preserveAspectRatio="none" role="group" :aria-label="`Grafik perbandingan pemasukan dan pengeluaran tiga ${yearly ? 'tahun' : 'bulan'}`" @pointerleave="hoveredKey = ''">
          <line v-for="tick in ticks" :key="tick.position" x1="0" x2="610" :y1="tick.position" :y2="tick.position" stroke="var(--chart-track)" stroke-dasharray="3 5" />
          <g v-for="row in series" :key="row.month">
            <rect v-for="bar in row.bars" :key="bar.kind" class="chart-segment" role="button" tabindex="0" :aria-label="`${bar.name} · ${row.label}`" :aria-pressed="selectedKey === `${row.month}:${bar.kind}`" :x="bar.x" :y="172 - Math.max(bar.height, 2)" width="28" :height="Math.max(bar.height, 2)" rx="5" :fill="`var(--chart-${bar.kind})`" :opacity="(hoveredKey || selectedKey) && (hoveredKey || selectedKey) !== `${row.month}:${bar.kind}` ? 0.3 : 1" @pointerenter="hoveredKey = `${row.month}:${bar.kind}`" @focus="hoveredKey = `${row.month}:${bar.kind}`" @blur="hoveredKey = ''" @click="select(`${row.month}:${bar.kind}`)" @keydown.enter.prevent="select(`${row.month}:${bar.kind}`)" @keydown.space.prevent="select(`${row.month}:${bar.kind}`)" />
          </g>
        </svg>
        <div class="flow-months" :style="{ gridTemplateColumns: `repeat(${series.length}, minmax(0, 1fr))` }"><span v-for="row in series" :key="row.month">{{ row.label }}</span></div>
      </div>
    </div>
    <div v-else class="flow-empty"><Icon name="reports" :size="32" /><h3>Belum ada arus keuangan</h3><p>Grafik muncul setelah ada transaksi.</p></div>
    <div v-if="selected" class="chart-inspector" role="status" aria-label="Rincian arus keuangan"><span class="chart-dot" :style="{ background: selected.color }"></span><strong>{{ selected.label }}</strong><Money :amount="selected.amount" /></div>
    <details class="flow-details"><summary>{{ yearly ? 'Lihat angka per tahun' : 'Lihat angka per bulan' }}</summary><div class="flow-values"><div class="flow-table-head"><span>{{ yearly ? 'Tahun' : 'Bulan' }}</span><span>Pemasukan</span><span>Pengeluaran</span></div><div v-for="row in series" :key="row.month"><strong>{{ row.label }}</strong><Money :amount="row.personalIncome" /><Money :amount="row.personalExpense" /></div></div></details>
  </section>
</template>
