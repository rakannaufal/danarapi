<script setup lang="ts">
import { computed } from 'vue';
import type { Bill } from '../domain.ts';
import { calculateReceipt } from '../item-split.ts';
import Money from './Money.vue';
const props = defineProps<{ bill: Bill }>();
const result = computed(() => { try { return props.bill.itemSplit?.settings ? calculateReceipt(props.bill.itemSplit, [...props.bill.members].sort((first, second) => first.sortOrder - second.sortOrder).map(member => member.id)) : null; } catch { return null; } });
</script>
<template>
  <details v-if="bill.itemSplit" class="receipt-breakdown"><summary>Menu dan rincian pembagian</summary><div v-for="item in bill.itemSplit.items" :key="item.id" class="receipt-history-item"><strong>{{ item.name }}</strong><span>{{ item.quantity }} × <Money :amount="item.unitPrice || '0'" /></span><small>{{ item.allocations.filter(entry => entry.quantity > 0).map(entry => bill.members.find(member => member.id === entry.memberID)?.displayName).filter(Boolean).join(', ') }}</small></div><div v-if="result" class="receipt-history-scroll"><table><caption class="sr-only">Rincian porsi tagihan tersimpan</caption><thead><tr><th scope="col">Nama</th><th scope="col">Pesanan</th><th scope="col">Diskon</th><th scope="col">Service</th><th scope="col">Pajak</th><th scope="col">Pembulatan</th><th scope="col">Bayar</th></tr></thead><tbody><tr v-for="row in result.rows" :key="row.id"><th scope="row">{{ bill.members.find(member => member.id === row.id)?.displayName }}</th><td v-for="key in (['subtotal','discount','service','tax','rounding','total'] as const)" :key="key"><Money :amount="row[key]" /></td></tr></tbody></table></div></details>
</template>
<style scoped>
.receipt-breakdown{margin:20px 0;padding:16px;border:1px solid var(--line);border-radius:16px}.receipt-breakdown summary{font-weight:600;cursor:pointer}.receipt-history-item{display:grid;grid-template-columns:1fr auto;gap:6px;padding:14px 0;border-bottom:1px dashed var(--line)}.receipt-history-item small{grid-column:1/-1;color:var(--muted)}.receipt-history-scroll{overflow-x:auto;margin-top:12px}.receipt-breakdown table{width:100%;border-collapse:collapse;font-size:13px;font-variant-numeric:tabular-nums}.receipt-breakdown th,.receipt-breakdown td{padding:10px 8px;text-align:right;white-space:nowrap;border-bottom:1px solid var(--line)}.receipt-breakdown th:first-child{text-align:left}.receipt-breakdown td:last-child{color:var(--primary);font-weight:700}
@media(max-width:600px){.receipt-history-item{grid-template-columns:1fr}}
</style>
