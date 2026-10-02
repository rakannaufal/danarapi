<script setup lang="ts">
import { ref } from 'vue';
import type { SavingsGoal } from '../domain.ts';
import type { PlanningEntry } from '../product.ts';
import PlanningHistory from './PlanningHistory.vue';
import { goalCountdown, progressPercent } from '../planning.ts';
import Money from './Money.vue';
import Icon from './Icon.vue';
defineProps<{ goal: SavingsGoal; day: string }>();
defineEmits<{ edit: [goal: SavingsGoal]; progress: [goal: SavingsGoal]; entry: [entry: PlanningEntry] }>();
const expanded = ref(false);
</script>
<template>
  <article class="goal-card">
    <div class="section-heading"><strong>{{ goal.name }}</strong><span class="deadline-pill" :class="{ overdue: goalCountdown(goal, day).startsWith('Lewat'), complete: BigInt(goal.savedAmount) >= BigInt(goal.targetAmount) }"><Icon :name="BigInt(goal.savedAmount) >= BigInt(goal.targetAmount) ? 'check' : 'calendar'" :size="14" />{{ goalCountdown(goal, day) }}</span></div>
    <div class="goal-amount"><Money :amount="goal.savedAmount" /><span class="muted"> / <Money :amount="goal.targetAmount" /></span></div>
    <progress :value="Number(goal.savedAmount)" :max="Number(goal.targetAmount)" :aria-label="`Progres target ${goal.name}`"></progress>
    <div class="goal-meta"><span>{{ Math.min(100, progressPercent(goal.savedAmount, goal.targetAmount)) }}% terkumpul</span><span v-if="goal.targetDate">{{ new Intl.DateTimeFormat('id-ID', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' }).format(new Date(`${goal.targetDate.slice(0,10)}T00:00:00Z`)) }}</span></div>
    <div class="button-row"><button class="secondary" @click="$emit('progress', goal)"><Icon name="plus" :size="16" /> Tambah progres</button><button class="text-button" @click="$emit('edit', goal)">Ubah target</button></div>
    <button class="text-button" :aria-expanded="expanded" @click="expanded = !expanded">{{ expanded ? 'Tutup rincian' : 'Lihat rincian' }}</button>
    <template v-if="expanded"><p v-if="goal.openingAmount && BigInt(goal.openingAmount) > 0n" class="fine-print">Progres awal <Money :amount="goal.openingAmount" /> tidak memindahkan saldo akun.</p><PlanningHistory :goal-i-d="goal.id" @entry="$emit('entry',$event)" /></template>
  </article>
</template>
