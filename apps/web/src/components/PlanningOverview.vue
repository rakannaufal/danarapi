<script setup lang="ts">
import { computed, ref, onMounted, onBeforeUnmount } from 'vue';
import { state } from '../store.ts';
import { localDay, type SavingsGoal } from '../domain.ts';
import { progressPercent, budgetStatus } from '../planning.ts';
import GoalCard from './GoalCard.vue';
import Money from './Money.vue';
import Icon from './Icon.vue';
import type { PlanningEntry } from '../product.ts';
const props = defineProps<{ month: string; targetsOnly?: boolean; overview?: boolean }>();
defineEmits<{ goal: [goal?: SavingsGoal]; budget: []; progress: [goal: SavingsGoal]; entry: [entry: PlanningEntry] }>();
const tick = ref(Date.now());
let timer: ReturnType<typeof setInterval> | undefined;
onMounted(() => { timer = setInterval(() => { tick.value = Date.now(); }, 60000); });
onBeforeUnmount(() => clearInterval(timer));
const day = computed(() => localDay(new Date(tick.value).toISOString(), state.timezone));
const goals = computed(() => [...(state.data.goals ?? [])].sort((left, right) => (left.targetDate ?? '9999').localeCompare(right.targetDate ?? '9999')));
const budgets = computed(() => state.data.budgets.filter(row => row.month.slice(0,7) === props.month));
const totalLimit = computed(() => budgets.value.reduce((sum, row) => sum + BigInt(row.limitAmount), 0n).toString());
const totalSpent = computed(() => budgets.value.reduce((sum, row) => sum + BigInt(row.spentAmount), 0n).toString());
const totalSaved = computed(() => goals.value.reduce((sum, row) => sum + BigInt(row.savedAmount), 0n).toString());
const totalTarget = computed(() => goals.value.reduce((sum, row) => sum + BigInt(row.targetAmount), 0n).toString());
const monthLabel = computed(() => new Intl.DateTimeFormat('id-ID', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(new Date(`${props.month}-01T00:00:00Z`)));
</script>
<template>
  <div class="planning-grid" :class="{ 'targets-only': targetsOnly, 'home-planning': overview }">
    <section class="card plan-panel" aria-label="Target tabungan">
      <div class="section-heading"><h2><Icon v-if="!overview" name="target" /> {{ overview ? 'Target tabungan' : 'Target' }}</h2><button class="text-button" @click="$emit('goal')"><Icon name="plus" :size="16" /> Tambah</button></div>
      <div v-if="goals.length && !overview" class="plan-summary"><span class="muted">{{ goals.length }} target · terkumpul</span><strong><Money :amount="totalSaved" /></strong><span class="fine-print">dari <Money :amount="totalTarget" /></span></div>
      <div v-if="!goals.length" class="plan-empty"><span class="icon-tile mint"><Icon name="target" :size="26" /></span><h3>Belum ada target</h3><button class="secondary" @click="$emit('goal')">Buat target</button></div>
      <div class="goal-list"><GoalCard v-for="goal in goals" :key="goal.id" :goal="goal" :day="day" @edit="$emit('goal', $event)" @progress="$emit('progress', $event)" @entry="$emit('entry',$event)" /></div>
    </section>
    <section v-if="!targetsOnly" class="card plan-panel" aria-label="Anggaran bulanan">
      <div class="section-heading"><h2><Icon name="budget" /> Anggaran</h2><button class="text-button" @click="$emit('budget')">Atur <Icon name="next" :size="16" /></button></div>
      <div class="plan-summary"><span class="muted">{{ monthLabel }}</span><strong><Money :amount="totalSpent" /></strong><span class="fine-print">terpakai dari <Money :amount="totalLimit" /></span></div>
      <div v-if="!budgets.length" class="plan-empty"><h3>Belum ada anggaran</h3><button class="secondary" @click="$emit('budget')">Buat anggaran</button></div>
      <div v-for="budget in budgets" :key="budget.id" class="plan-budget" :class="budgetStatus(budget.spentAmount, budget.limitAmount)">
        <div class="section-heading"><strong>{{ state.data.categories.find(category => category.id === budget.categoryID)?.name ?? 'Kategori' }}</strong><span>{{ progressPercent(budget.spentAmount, budget.limitAmount) }}%</span></div>
        <progress :value="Number(budget.spentAmount)" :max="Number(budget.limitAmount)" :aria-label="`Anggaran ${state.data.categories.find(category => category.id === budget.categoryID)?.name}`"></progress>
        <div class="goal-meta"><span><Money :amount="budget.spentAmount" /> / <Money :amount="budget.limitAmount" /></span><span>{{ BigInt(budget.spentAmount) > BigInt(budget.limitAmount) ? 'Melebihi batas' : BigInt(budget.spentAmount) === BigInt(budget.limitAmount) ? 'Batas tercapai' : 'Sisa' }} <Money v-if="BigInt(budget.spentAmount) !== BigInt(budget.limitAmount)" :amount="String(BigInt(budget.spentAmount) > BigInt(budget.limitAmount) ? BigInt(budget.spentAmount) - BigInt(budget.limitAmount) : BigInt(budget.limitAmount) - BigInt(budget.spentAmount))" /></span></div>
      </div>
    </section>
  </div>
</template>
