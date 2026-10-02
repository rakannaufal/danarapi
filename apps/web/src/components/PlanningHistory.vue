<script setup lang="ts">
import { ref, watch } from 'vue';
import { state, planningHistory, message } from '../store.ts';
import { fromZonedTime } from '../timezone.ts';
import type { PlanningEntry, PlanningHistory } from '../product.ts';
import Money from './Money.vue';
const props = defineProps<{ goalID?: string; categoryID?: string; month?: string }>();
defineEmits<{ entry: [entry: PlanningEntry] }>();
const entries = ref<PlanningEntry[]>([]), cursor = ref<PlanningHistory['nextCursor']>(null), loading = ref(false), error = ref('');
let revision = 0;
async function refresh(more = false) {
  const current = ++revision; loading.value = true; error.value = '';
  const startDate = props.month ? fromZonedTime(`${props.month.slice(0,7)}-01`, state.timezone) : undefined;
  const next = props.month ? new Date(`${props.month.slice(0,7)}-01T00:00:00Z`) : undefined;
  next?.setUTCMonth(next.getUTCMonth() + 1);
  const endDate = next ? fromZonedTime(next.toISOString().slice(0,10), state.timezone) : undefined;
  if (!more) entries.value = [];
  try {
    const result = await planningHistory({ goalID: props.goalID, categoryID: props.categoryID, startDate, endDate, cursor: more ? cursor.value : null });
    if (current !== revision) return;
    entries.value = more ? [...entries.value, ...result.items.filter(row => !entries.value.some(item => item.id === row.id))] : result.items;
    cursor.value = result.nextCursor;
  } catch (cause) { if (current === revision) error.value = message(cause); }
  finally { if (current === revision) loading.value = false; }
}
watch(() => [props.goalID,props.categoryID,props.month,state.data,state.timezone], () => refresh(), { immediate: true });
</script>
<template>
  <section class="planning-history">
    <h3>{{ goalID ? 'Riwayat kontribusi' : 'Pengeluaran pembentuk realisasi' }}</h3>
    <div v-if="loading && !entries.length" role="status">Memuat riwayat…</div>
    <div v-if="error" role="alert"><p class="error-text">{{ error }}</p><button class="secondary" @click="refresh(!!entries.length)">Coba lagi</button></div>
    <p v-if="!loading && !error && !entries.length" class="muted">Belum ada catatan.</p>
    <button v-for="entry in entries" :key="entry.id" class="transaction-row" @click="$emit('entry',entry)"><span class="row-copy"><strong>{{ entry.merchant || (entry.kind === 'split_bill' ? 'Porsi split bill' : entry.kind === 'split_resolution' ? 'Penyelesaian split bill' : 'Kontribusi') }}</strong><span>{{ new Date(entry.occurredAt).toLocaleDateString('id-ID',{ timeZone: state.timezone }) }}{{ entry.note ? ` · ${entry.note}` : '' }}</span></span><Money :amount="entry.amount" /></button>
    <button v-if="cursor" class="secondary" :disabled="loading" @click="refresh(true)">{{ loading ? 'Memuat…' : 'Muat lagi' }}</button>
  </section>
</template>
