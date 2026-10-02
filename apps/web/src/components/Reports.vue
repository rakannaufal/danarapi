<script setup lang="ts">
import { ref, watch, computed } from 'vue';
import { state, report, loadReport, today, message } from '../store.ts';
import { exportCSVs, download } from '../export.ts';
import { cashFlows, reportFor, localDay, type Bill } from '../domain.ts';
import { chartColor, chartPercent, chartPalette } from '../report-charts.ts';
import { budgetStatus } from '../planning.ts';
import { allocationBreakdown } from '../../../../supabase/functions/_shared/planning.ts';
import Money from './Money.vue';
import Icon from './Icon.vue';
import DonutChart from './DonutChart.vue';
import FlowChart from './FlowChart.vue';
const emit = defineEmits<{ bill: [bill: Bill]; budget: [] }>();
const period = ref<'month' | 'year'>('month'), month = ref(today().slice(0, 7)), loading = ref(false), error = ref('');
const range = computed(() => {
  const [year, selectedMonth] = month.value.split('-').map(Number);
  return period.value === 'year' ? { from: `${year}-01-01`, to: `${year}-12-31` } : { from: `${month.value}-01`, to: `${month.value}-${new Date(Date.UTC(year, selectedMonth, 0)).getUTCDate()}` };
});
const periodLabel = computed(() => period.value === 'year' ? month.value.slice(0, 4) : new Intl.DateTimeFormat('id-ID', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(new Date(`${month.value}-01T00:00:00Z`)));
const difference = computed(() => BigInt(report.value.personalIncome) - BigInt(report.value.personalExpense));
const cash = computed(() => cashFlows(state.data, range.value.from, range.value.to, state.timezone));
const trends = computed(() => Array.from({ length: 3 }, (_, index) => {
  const [year, selectedMonth] = month.value.split('-').map(Number);
  const date = new Date(Date.UTC(period.value === 'year' ? year - 2 + index : year, period.value === 'year' ? 0 : selectedMonth - 3 + index, 1));
  if (period.value === 'year') { const selectedYear = date.getUTCFullYear(); return { month: String(selectedYear), ...reportFor(state.data, `${selectedYear}-01-01`, `${selectedYear}-12-31`, state.timezone) }; }
  const key = date.toISOString().slice(0, 7), end = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)).getUTCDate();
  return { month: key, ...reportFor(state.data, `${key}-01`, `${key}-${end}`, state.timezone) };
}));
const allocations = computed(() => report.value.allocations ?? allocationBreakdown(report.value.categories, state.data.transactions.filter(row => !row.deleted && row.kind === 'expense' && row.goalID && localDay(row.occurredAt, state.timezone) >= range.value.from && localDay(row.occurredAt, state.timezone) <= range.value.to).map(row => ({ categoryID: row.categoryID, goalID: row.goalID!, amount: row.amount })), state.data.goals ?? [], state.data.categories, new Set(state.data.budgets.filter(row => row.month.slice(0, 7) >= range.value.from.slice(0, 7) && row.month.slice(0, 7) <= range.value.to.slice(0, 7)).map(row => row.categoryID))));
const flows = computed(() => [{ id: 'income', name: 'Pemasukan', amount: report.value.personalIncome }, { id: 'expense', name: 'Pengeluaran', amount: report.value.personalExpense }]);
const palette = computed(() => chartPalette([...report.value.categories.map(row => row.categoryID), ...allocations.value.map(row => row.id)]));
function categoryColor(identifier: string) { return palette.value.get(identifier.replace(/^category:/, '')) ?? chartColor(identifier); }
const coloredAllocations = computed(() => allocations.value.map(row => ({ ...row, color: categoryColor(row.id) })));
const categories = computed(() => [...report.value.categories].sort((left, right) => BigInt(left.amount) > BigInt(right.amount) ? -1 : BigInt(left.amount) < BigInt(right.amount) ? 1 : left.categoryID.localeCompare(right.categoryID)));
const budgets = computed(() => {
  const grouped = new Map<string, { categoryID: string; spent: bigint; limit: bigint }>();
  for (const budget of state.data.budgets.filter(row => row.month.slice(0, 7) >= range.value.from.slice(0, 7) && row.month.slice(0, 7) <= range.value.to.slice(0, 7))) {
    const row = grouped.get(budget.categoryID) ?? { categoryID: budget.categoryID, spent: 0n, limit: 0n };
    row.spent += BigInt(budget.spentAmount); row.limit += BigInt(budget.limitAmount); grouped.set(row.categoryID, row);
  }
  return [...grouped.values()];
});
function categoryName(identifier: string) { return state.data.categories.find(category => category.id === identifier)?.name ?? 'Kategori'; }
function selectMonth(event: Event) {
  const input = event.target as HTMLInputElement;
  if (/^\d{4}-(0[1-9]|1[0-2])$/.test(input.value)) month.value = input.value;
  else input.value = month.value;
}
function movePeriod(offset: number) {
  const [year, selectedMonth] = month.value.split('-').map(Number);
  month.value = new Date(Date.UTC(year + (period.value === 'year' ? offset : 0), selectedMonth - 1 + (period.value === 'month' ? offset : 0), 1)).toISOString().slice(0, 7);
}
let revision = 0;
async function refresh() { const current = ++revision; loading.value = true; error.value = ''; try { await loadReport(range.value.from, range.value.to); } catch (cause) { if (current === revision) error.value = message(cause); } finally { if (current === revision) loading.value = false; } }
watch([range, () => state.data, () => state.timezone], refresh, { immediate: true });
function exportCSV(name: string) { const files = exportCSVs(state.data, range.value.from, range.value.to, state.timezone); download(name, files[name as keyof typeof files]); state.notice = `CSV periode ${range.value.from} sampai ${range.value.to} diunduh.`; }
</script>
<template>
  <div class="reports-page">
    <div class="report-toolbar">
      <div class="report-period"><button class="icon-button" aria-label="Periode sebelumnya" @click="movePeriod(-1)"><Icon name="back" :size="18" /></button><label>Periode<input :value="month" type="month" required @input="selectMonth"></label><button class="icon-button" aria-label="Periode berikutnya" @click="movePeriod(1)"><Icon name="next" :size="18" /></button></div>
      <div class="segmented compact"><button :class="{ active: period === 'month' }" :aria-pressed="period === 'month'" @click="period = 'month'">Bulanan</button><button :class="{ active: period === 'year' }" :aria-pressed="period === 'year'" @click="period = 'year'">Tahunan</button></div>
      <details class="export-menu"><summary class="secondary"><Icon name="download" :size="18" /> Ekspor CSV</summary><button v-for="name in Object.keys(exportCSVs(state.data))" :key="name" class="text-button" @click="exportCSV(name)">{{ name }}</button></details>
    </div>
    <div v-if="loading" class="report-loading" role="status"><span class="provider-spinner"></span>Memuat laporan…</div>
    <div v-else-if="error" role="alert" class="callout"><p>{{ error }}</p><button class="secondary" @click="refresh">Coba lagi</button></div>
    <template v-else>
      <div class="report-stats">
        <article class="card report-metric"><span class="report-metric-label"><Icon name="income" :size="18" />Pemasukan</span><h2 class="income-value"><Money :amount="report.personalIncome" prefix="+" /></h2><span class="fine-print">{{ periodLabel }}</span></article>
        <article class="card report-metric"><span class="report-metric-label"><Icon name="expense" :size="18" />Pengeluaran</span><h2 class="expense-value"><Money :amount="report.personalExpense" prefix="−" /></h2><span class="fine-print">{{ periodLabel }}</span></article>
        <article class="card report-metric"><span class="report-metric-label"><Icon name="wallet" :size="18" />Selisih periode</span><h2><Money :amount="difference < 0n ? -difference : difference" :prefix="difference < 0n ? '−' : difference > 0n ? '+' : ''" /></h2><span class="fine-print">Pemasukan dikurangi pengeluaran</span></article>
      </div>
      <FlowChart :yearly="period === 'year'" :rows="trends" />
      <div class="report-charts"><DonutChart title="Alokasi pengeluaran" :rows="coloredAllocations" /><DonutChart title="Pemasukan & pengeluaran" :rows="flows" show-zero-rows /></div>
      <div class="report-detail-grid">
        <section class="card report-breakdown"><div class="section-heading"><h2>Pengeluaran per kategori</h2><Icon name="reports" :size="19" /></div><div v-if="!categories.length" class="chart-empty"><Icon name="reports" :size="26" /><span>Belum ada pengeluaran</span></div><div v-for="row in categories" :key="row.categoryID" class="report-category"><div class="section-heading"><span>{{ categoryName(row.categoryID) }}</span><Money :amount="row.amount" /></div><div class="report-category-track" role="progressbar" :aria-label="`Pengeluaran kategori ${categoryName(row.categoryID)}`" :aria-valuenow="chartPercent(row.amount, report.personalExpense)" aria-valuemin="0" aria-valuemax="100"><span :style="{ width: `${chartPercent(row.amount, report.personalExpense)}%`, background: categoryColor(row.categoryID) }"></span></div></div></section>
        <section class="card report-budgets"><div class="section-heading"><h2>Anggaran</h2><button class="text-button" @click="emit('budget')">Kelola <Icon name="next" :size="16" /></button></div><div v-if="!budgets.length" class="chart-empty"><Icon name="budget" :size="26" /><span>Belum ada anggaran periode ini</span><button class="secondary" @click="emit('budget')">Atur anggaran</button></div><div v-for="row in budgets" :key="row.categoryID" class="report-category" :class="budgetStatus(String(row.spent), String(row.limit))"><div class="section-heading"><span>{{ categoryName(row.categoryID) }}</span><strong>{{ row.limit > 0n ? Number(row.spent * 100n / row.limit).toLocaleString('id-ID') : 0 }}%</strong></div><progress :value="chartPercent(row.spent, row.limit)" max="100" :aria-label="`Anggaran ${categoryName(row.categoryID)}`"></progress><div class="goal-meta"><Money :amount="row.spent" /><span>dari <Money :amount="row.limit" /></span></div></div></section>
      </div>
      <section class="card cash-report"><div class="section-heading"><h2>Arus kas per akun</h2><Icon name="wallet" :size="19" /></div><div v-for="row in cash" :key="row.accountID" class="cash-account"><h3>{{ state.data.accounts.find(account => account.id === row.accountID)?.name ?? 'Akun' }}</h3><div class="cash-metrics"><span>Masuk<strong class="income-value"><Money :amount="row.incoming" prefix="+" /></strong></span><span>Keluar<strong class="expense-value"><Money :amount="row.outgoing" prefix="−" /></strong></span><span>Arus bersih<strong><Money :amount="row.net" /></strong></span></div></div><details class="help-disclosure"><summary>Tentang laporan</summary><p>Pengeluaran menghitung porsi Anda. Arus kas mencatat seluruh uang masuk dan keluar akun. Transfer dan pelunasan tidak dihitung dua kali.</p></details></section>
      <details class="card report-position"><summary>Posisi akun saat ini</summary><div class="list-row"><span>Piutang</span><Money :amount="state.data.overview.receivables" /></div><div class="list-row"><span>Utang</span><Money :amount="state.data.overview.payables" /></div><div class="list-row"><strong>Posisi bersih</strong><Money :amount="state.data.overview.netPosition" /></div><p class="fine-print">Saldo terkini, bukan saldo penutupan periode.</p></details>
    </template>
  </div>
</template>
