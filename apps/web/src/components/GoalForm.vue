<script setup lang="ts">
import MoneyInput from './MoneyInput.vue';
import { reactive, ref, watch } from 'vue';
import { state, mutate, mutation } from '../store.ts';
import { id, localDay, type SavingsGoal } from '../domain.ts';
import { parseMoney } from '../contracts.ts';
const props = defineProps<{ goal?: SavingsGoal }>();
const emit = defineEmits<{ saved: []; dirty: [value: boolean] }>();
const nextMonth = new Date(`${localDay(new Date().toISOString(), state.timezone)}T00:00:00Z`); nextMonth.setUTCDate(nextMonth.getUTCDate() + 30);
const form = reactive({ name: props.goal?.name ?? '', target: props.goal?.targetAmount ?? '', saved: props.goal?.openingAmount ?? props.goal?.savedAmount ?? '0', date: props.goal?.targetDate?.slice(0, 10) ?? nextMonth.toISOString().slice(0, 10) });
const goalID = props.goal?.id ?? id();
const error = ref('');
watch(form, () => emit('dirty', true));
async function save() {
  error.value = '';
  try {
    parseMoney(form.target); parseMoney(form.saved, true);
    if (!form.name.trim() || !form.date) throw new Error();
    if (await mutate('save_goal', { ...mutation(), p_id: goalID, p_name: form.name.trim(), p_target: form.target, p_saved: form.saved, p_target_date: form.date, p_expected_version: props.goal?.version ?? 0 }, 'Target tersimpan')) { emit('dirty', false); emit('saved'); }
  } catch { error.value = 'Periksa nama, nominal, dan tanggal target.'; }
}
async function remove() {
  if (!props.goal || !window.confirm('Hapus target ini? Saldo akun tidak berubah.')) return;
  if (await mutate('delete_goal', { ...mutation(), p_id: props.goal.id, p_expected_version: props.goal.version }, 'Target dihapus')) { emit('dirty', false); emit('saved'); }
}
</script>
<template>
  <form class="entry-form planning-form" @submit.prevent="save">
    <label>Nama target<input v-model="form.name" maxlength="100" required placeholder="Dana darurat, liburan, atau laptop"></label>
    <label>Total target (Rp)<MoneyInput v-model="form.target" required placeholder="5.000.000" /></label>
    <label>Tanggal target<input v-model="form.date" type="date" required></label>
    
    <p v-if="error || state.error" class="error-text" role="alert">{{ error || state.error }}</p>
    <div class="button-row"><button class="primary" :disabled="state.saving || (!state.online && state.mode !== 'demo')">{{ state.saving ? 'Menyimpan…' : 'Simpan target' }}</button><button v-if="goal" type="button" class="text-button danger-text" :disabled="state.saving" @click="remove">Hapus target</button></div>
  </form>
</template>
