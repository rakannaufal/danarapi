<script setup lang="ts">
import { computed } from 'vue';
import { state, preferences } from '../store.ts';
import { billRemaining, billStatus, type Report, type ListRow, type Bill, type SavingsGoal } from '../domain.ts';
import Money from './Money.vue';
import Icon from './Icon.vue';
import PlanningOverview from './PlanningOverview.vue';
import type { PlanningEntry } from '../product.ts';
const props = defineProps<{ month: string; report: Report; pending: number; rows: ListRow[]; bills: Bill[] }>();
const emit = defineEmits<{ 'update:month': [value: string]; accounts: []; transactions: []; income: []; expense: []; review: []; add: []; topup: []; targets: []; goal: [goal?: SavingsGoal]; progress: [goal: SavingsGoal]; budget: []; row: [row: ListRow]; bill: [bill: Bill]; entry: [entry: PlanningEntry] }>();
const accounts = computed(() => state.data.accounts.filter(account => !account.archived));
const totalSaved = computed(() => (state.data.goals ?? []).reduce((sum, goal) => sum + BigInt(goal.savedAmount), 0n).toString());
const totalBudget = computed(() => state.data.budgets.filter(budget => budget.month.slice(0, 7) === props.month).reduce((sum, budget) => sum + BigInt(budget.limitAmount), 0n).toString());
const monthLabel = computed(() => new Intl.DateTimeFormat('id-ID', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(new Date(`${props.month}-01T00:00:00Z`)));
function categoryName(identifier: string) { return state.data.categories.find(category => category.id === identifier)?.name ?? 'Antar akun'; }
function kindLabel(kind: string) { return ({ income: 'Pemasukan', expense: 'Pengeluaran', transfer: 'Transfer', split: 'Split bill' } as Record<string, string>)[kind] ?? 'Catatan'; }
function dateLabel(value: string) { return new Intl.DateTimeFormat('id-ID', { timeZone: state.timezone, day: 'numeric', month: 'short' }).format(new Date(value)); }
function selectMonth(event: Event) {
  const input = event.target as HTMLInputElement;
  if (/^\d{4}-(0[1-9]|1[0-2])$/.test(input.value)) emit('update:month', input.value);
  else input.value = props.month;
}
</script>
<template>
  <div class="home-page">
    <div class="home-period-bar"><span>{{ monthLabel }}</span><label class="home-month"><Icon name="calendar" :size="17" />Ganti periode<input :value="month" type="month" aria-label="Periode beranda" @input="selectMonth"></label></div>
    <div class="home-overview">
      <section class="card home-balance" aria-label="Ringkasan saldo">
        <div class="balance-top"><span class="balance-label"><Icon name="wallet" :size="18" />Saldo akun</span><button class="balance-visibility" :aria-label="state.hideAmounts ? 'Tampilkan nominal saldo' : 'Sembunyikan nominal saldo'" @click="state.hideAmounts = !state.hideAmounts; preferences()"><Icon :name="state.hideAmounts ? 'hidden' : 'eye'" /></button></div>
        <button class="home-balance-value" aria-label="Lihat saldo akun" @click="$emit('accounts')"><strong><Money :amount="state.data.overview.accountBalance" /></strong><span>{{ accounts.length }} akun aktif <Icon name="next" :size="16" /></span></button>
        <div class="balance-actions"><button class="balance-review" aria-label="Tinjau bukti" @click="$emit('review')"><Icon name="review" :size="20" />Tinjau <span v-if="pending" class="balance-count">{{ pending }}</span></button><button class="balance-topup" @click="$emit('topup')"><Icon name="plus" :size="20" />Tambah saldo</button></div>
      </section>
      <div class="home-summary-grid">
        <button class="card home-metric" aria-label="Lihat pemasukan" @click="$emit('income')"><span class="metric-top"><span class="icon-tile mint"><Icon name="income" :size="22" /></span><Icon name="next" :size="16" /></span><span class="home-label">Pemasukan</span><strong class="income-value"><Money :amount="report.personalIncome" /></strong></button>
        <button class="card home-metric" aria-label="Lihat pengeluaran" @click="$emit('expense')"><span class="metric-top"><span class="icon-tile peach"><Icon name="expense" :size="22" /></span><Icon name="next" :size="16" /></span><span class="home-label">Pengeluaran</span><strong><Money :amount="report.personalExpense" /></strong></button>
        <button class="card home-metric" aria-label="Lihat target tabungan" @click="$emit('targets')"><span class="metric-top"><span class="icon-tile mint"><Icon name="target" :size="22" /></span><Icon name="next" :size="16" /></span><span class="home-label">Target terkumpul</span><strong class="income-value"><Money :amount="totalSaved" /></strong></button>
        <button class="card home-metric" aria-label="Lihat anggaran" @click="$emit('budget')"><span class="metric-top"><span class="icon-tile peach"><Icon name="budget" :size="22" /></span><Icon name="next" :size="16" /></span><span class="home-label">Total anggaran</span><strong><Money :amount="totalBudget" /></strong></button>
      </div>
    </div>
    <PlanningOverview :month="month" overview @goal="$emit('goal', $event)" @progress="$emit('progress', $event)" @budget="$emit('budget')" @entry="$emit('entry',$event)" />
    <div class="home-detail-grid">
      <section class="card home-recent"><div class="section-heading"><h2>Catatan terbaru</h2><button class="text-button" @click="$emit('transactions')">Lihat semua <Icon name="next" :size="16" /></button></div><div v-if="!rows.length" class="chart-empty"><Icon name="file" :size="28" /><h3>Belum ada transaksi</h3><button class="secondary" @click="$emit('add')">Catat pengeluaran</button></div><button v-for="row in rows" :key="row.id" class="transaction-row" @click="$emit('row', row)"><span class="icon-tile" :class="row.kind === 'income' ? 'mint' : row.kind === 'expense' ? 'peach' : 'sky'"><Icon :name="row.kind" :size="18" /></span><span class="row-copy"><strong>{{ row.merchant || kindLabel(row.kind) }}</strong><span>{{ categoryName(row.categoryID) }} · {{ dateLabel(row.occurredAt) }}</span></span><span class="row-amount"><Money :amount="row.amount" :prefix="row.kind === 'income' ? '+' : row.kind === 'expense' ? '−' : ''" /></span></button></section>
      <section class="card home-accounts"><div class="section-heading"><h2>Akun keuangan</h2><button class="text-button" @click="$emit('accounts')">Kelola <Icon name="next" :size="16" /></button></div><button v-for="account in accounts" :key="account.id" class="home-account-row" @click="$emit('accounts')"><span class="icon-tile sky"><Icon :name="account.kind === 'bank' ? 'bank' : 'wallet'" :size="18" /></span><span>{{ account.name }}</span><Money :amount="account.balance" /></button></section>
    </div>
    <section v-if="bills.length" class="card home-bills"><div class="section-heading"><h2>Tagihan bersama</h2><span class="fine-print">{{ bills.length }} belum selesai</span></div><button v-for="bill in bills" :key="bill.id" class="bill-row" @click="$emit('bill', bill)"><span class="icon-tile sky"><Icon name="split" :size="18" /></span><span class="row-copy"><strong>{{ bill.title }}</strong><span>{{ billStatus(bill) }}</span></span><Money :amount="billRemaining(bill)" /><Icon name="next" :size="16" /></button></section>
  </div>
</template>
