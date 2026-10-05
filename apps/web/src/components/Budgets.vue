<script setup lang="ts">
import MoneyInput from './MoneyInput.vue';
import PlanningHistory from './PlanningHistory.vue';
import type { PlanningEntry } from '../product.ts';
import { computed, ref, watch, nextTick } from 'vue';
import { state, mutate, mutation, today } from '../store.ts';
import { normalize, money } from '../domain.ts';
import { parseMoney } from '../contracts.ts';
import { budgetPresets, progressPercent, budgetStatus } from '../planning.ts';
import Money from './Money.vue';
import Icon from './Icon.vue';
import type { Budget } from '../domain.ts';
const props = defineProps<{ compact?: boolean; initialMonth?: string }>();
const emit = defineEmits<{ saved: []; dirty: [value: boolean]; entry: [entry: PlanningEntry] }>();
const month = ref(props.initialMonth ?? today().slice(0,7)), category = ref(''), newCategory = ref(''), limit = ref(''), error = ref('');
const editing = ref(false);
const expanded = ref('');
async function removeBudget(budget: Budget) {
  if (!window.confirm('Hapus anggaran bulan ini? Hanya limit ini yang dihapus. Transaksi, kategori, dan anggaran bulan lain tetap tersimpan.')) return;
  if (await mutate('delete_budget', { id: budget.id, expected_limit: budget.limitAmount }, 'Anggaran dihapus')) {
    if (expanded.value === budget.id) expanded.value = '';
    if (category.value === budget.categoryID) { editing.value = false; limit.value = ''; category.value = ''; }
    emit('dirty', false); emit('saved');
  }
}
async function copyNextMonth() {
  const next = new Date(`${month.value}-01T00:00:00Z`); next.setUTCMonth(next.getUTCMonth() + 1);
  const destination = next.toISOString().slice(0,7);
  if (!window.confirm(`Salin limit ke ${destination}? Anggaran yang sudah ada tidak ditimpa. Saldo tidak berubah.`)) return;
  if (await mutate('copy_budgets',{ from: `${month.value}-01`,to: `${destination}-01` },'Rencana anggaran disalin')) month.value = destination;
}
const editor = ref<HTMLFormElement>();
const categories = computed(() => state.data.categories.filter(item => !item.archived && item.kind === 'expense'));
const budgets = computed(() => state.data.budgets.filter(row => row.month.slice(0,7) === month.value));
const totals = computed(() => ({ limit: budgets.value.reduce((sum, row) => sum + BigInt(row.limitAmount), 0n), spent: budgets.value.reduce((sum, row) => sum + BigInt(row.spentAmount), 0n) }));
async function beginEdit(categoryID = '') {
  category.value = categoryID; newCategory.value = ''; error.value = '';
  limit.value = budgets.value.find(row => row.categoryID === categoryID)?.limitAmount ?? '';
  editing.value = true;
  await nextTick(); editor.value?.querySelector<HTMLElement>('select')?.focus();
}
function cancelEdit() {
  if ((limit.value || newCategory.value) && !window.confirm('Buang perubahan anggaran?')) return;
  editing.value = false; category.value = ''; newCategory.value = ''; limit.value = ''; error.value = '';
  emit('dirty', false);
}
watch([month, category, newCategory, limit], () => emit('dirty', true));
function choose(name: string) {
  const existing = categories.value.find(row => normalize(row.name) === normalize(name));
  category.value = existing?.id ?? 'new'; newCategory.value = existing ? '' : name;
  const budget = existing && budgets.value.find(row => row.categoryID === existing.id);
  limit.value = budget ? budget.limitAmount : '';
}
async function save() {
  error.value = '';
  try {
    parseMoney(limit.value);
    if (!/^\d{4}-\d{2}$/.test(month.value) || !category.value) throw new Error();
    let categoryID = category.value;
    if (categoryID === 'new') {
      const name = newCategory.value.trim(); if (!name || name.length > 80) throw new Error();
      let existing = categories.value.find(row => normalize(row.name) === normalize(name));
      if (!existing) {
        if (!await mutate('create_category', { ...mutation(), p_name: name, p_kind: 'expense', p_sort_order: state.data.categories.length }, 'Kategori dibuat')) return;
        existing = categories.value.find(row => normalize(row.name) === normalize(name));
      }
      if (!existing) throw new Error(); categoryID = existing.id; category.value = categoryID;
    }
    if (await mutate('upsert_budget', { category_id: categoryID, month: `${month.value}-01`, limit_amount: limit.value }, 'Anggaran tersimpan')) { limit.value = ''; editing.value = false; emit('dirty', false); emit('saved'); }
  } catch { error.value = 'Pilih kategori, bulan, dan limit Rupiah positif.'; }
}
</script>
<template>
  <div class="budget-page">
    <div v-if="!compact && !editing" class="planning-toolbar"><label>Periode anggaran<input v-model="month" type="month" required></label><button class="primary" @click="beginEdit()">Tambah anggaran</button></div>
    <div v-if="!compact && !editing" class="planning-summary"><article class="card"><span class="muted">Total anggaran</span><strong><Money :amount="String(totals.limit)" /></strong></article><article class="card"><span class="muted">Terpakai</span><strong><Money :amount="String(totals.spent)" /></strong><span class="budget-percent" aria-label="Persentase total anggaran terpakai">{{ progressPercent(String(totals.spent), String(totals.limit)).toLocaleString('id-ID') }}% terpakai</span></article><article class="card"><span class="muted">{{ totals.spent > totals.limit ? 'Melebihi batas' : 'Sisa anggaran' }}</span><strong :class="{ 'danger-text': totals.spent > totals.limit }"><Money :amount="String(totals.spent > totals.limit ? totals.spent - totals.limit : totals.limit - totals.spent)" /></strong></article></div>
    <form v-if="compact || editing" ref="editor" class="entry-form planning-form" :class="{ card: !compact }" @submit.prevent="save">
      <div v-if="!compact" class="section-heading"><h2>Atur anggaran</h2><button type="button" class="text-button" @click="cancelEdit">Batal</button></div>
      <label>Bulan anggaran<input v-model="month" type="month" required></label>
      <fieldset class="preset-fieldset"><legend>Kategori siap pakai</legend><div class="preset-grid"><button v-for="name in budgetPresets" :key="name" type="button" class="preset-chip" :class="{ selected: newCategory === name || categories.find(row => row.id === category)?.name === name }" :aria-pressed="newCategory === name || categories.find(row => row.id === category)?.name === name" @click="choose(name)">{{ name }}</button></div></fieldset>
      <label>Kategori<select v-model="category" required><option value="" disabled>Pilih kategori</option><option v-for="row in categories" :key="row.id" :value="row.id">{{ row.name }}</option><option value="new">+ Buat kategori sendiri</option></select></label>
      <label v-if="category === 'new'">Nama kategori<input v-model="newCategory" maxlength="80" required placeholder="Contoh: Perawatan hewan"></label>
      <label>Limit bulanan<MoneyInput v-model="limit" required placeholder="1.000.000" /></label>
      <p v-if="error || state.error" class="error-text" role="alert">{{ error || state.error }}</p>
      <button class="primary" :disabled="state.saving || (!state.online && state.mode !== 'demo')">{{ state.saving ? 'Menyimpan…' : 'Simpan anggaran' }}</button>
    </form>
    <template v-if="!compact">
      <div class="section-heading"><h2>Anggaran bulan ini</h2><span class="muted">{{ budgets.length }} kategori</span></div>
      <button v-if="budgets.length" class="secondary" :disabled="state.saving || (!state.online && state.mode !== 'demo')" @click="copyNextMonth">Salin ke bulan berikutnya</button>
      <p v-if="!budgets.length" class="muted">Belum ada anggaran pada bulan ini.</p>
      <div class="budget-list">
<article v-for="budget in budgets" :key="budget.id" class="card budget-card" :class="budgetStatus(budget.spentAmount, budget.limitAmount)">
        <div class="section-heading"><h3>{{ state.data.categories.find(row => row.id === budget.categoryID)?.name }}</h3><div class="button-row"><button class="text-button" @click="beginEdit(budget.categoryID)">Ubah limit</button><button class="icon-button danger-text" :aria-label="`Hapus anggaran ${state.data.categories.find(row => row.id === budget.categoryID)?.name}`" :disabled="state.saving" @click="removeBudget(budget)"><Icon name="trash" :size="18" /></button></div></div>
        <div class="section-heading"><span><Money :amount="budget.spentAmount" /> / <Money :amount="budget.limitAmount" /></span><strong class="budget-percent">{{ progressPercent(budget.spentAmount, budget.limitAmount).toLocaleString('id-ID') }}%</strong></div>
        <progress :value="Number(budget.spentAmount)" :max="Number(budget.limitAmount)" :aria-label="`Anggaran ${state.data.categories.find(row => row.id === budget.categoryID)?.name}`"></progress>
        <button class="text-button" :aria-expanded="expanded === budget.id" @click="expanded = expanded === budget.id ? '' : budget.id">{{ expanded === budget.id ? 'Tutup rincian' : 'Lihat rincian' }}</button>
        <PlanningHistory v-if="expanded === budget.id" :category-i-d="budget.categoryID" :month="month" @entry="$emit('entry',$event)" />
        <p :class="{ 'danger-text': BigInt(budget.spentAmount) > BigInt(budget.limitAmount) }">{{ BigInt(budget.spentAmount) > BigInt(budget.limitAmount) ? 'Melebihi batas' : 'Sisa' }} {{ state.hideAmounts ? 'Rp••••••' : money(BigInt(budget.spentAmount) > BigInt(budget.limitAmount) ? BigInt(budget.spentAmount) - BigInt(budget.limitAmount) : BigInt(budget.limitAmount) - BigInt(budget.spentAmount)) }}</p>
      </article>
</div>
    </template>
  </div>
</template>
