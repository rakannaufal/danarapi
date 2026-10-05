<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue';
import { calculatorCatalog, calculatorDefaults, calculatorRow, calculatorSummary, calculate, visibleCalculatorField, type CalculatorDefinition, type CalculatorResult, type CalculationRecord } from '../calculators.ts';
import { state, mutate, calculatorOwnerID, today } from '../store.ts';
import Icon from './Icon.vue';
import Modal from './Modal.vue';
import MoneyInput from './MoneyInput.vue';

const search = ref(''), category = ref('all'), onlyFavorites = ref(false);
const selected = ref<CalculatorDefinition>(), information = ref(false), result = ref<CalculatorResult>(), error = ref(''), calculated = ref(false), draftSaved = ref(false);
const inputs = reactive<Record<string, string>>({});
const favorites = ref<string[]>([]), history = ref<CalculationRecord[]>([]), historyOpen = ref(false);
const owner = computed(() => { void state.email; void state.data; return calculatorOwnerID(); });
const storageKey = (suffix: string) => `danarapi.calculators.${owner.value}.${suffix}`;
function loadPreferences() {
  try { favorites.value = JSON.parse(localStorage.getItem(storageKey('favorites')) ?? '[]').filter((id: string) => calculatorCatalog.calculators.some(row => row.id === id)); } catch { favorites.value = []; }
  try { history.value = JSON.parse(sessionStorage.getItem(storageKey('history')) ?? '[]').filter((row: CalculationRecord) => calculatorCatalog.calculators.some(def => def.id === row.calculatorID)).slice(0, 20); } catch { history.value = []; }
}
watch(owner, () => { selected.value = undefined; result.value = undefined; information.value = false; historyOpen.value = false; clearInputs(); loadPreferences(); }, { immediate: true });
const filtered = computed(() => calculatorCatalog.calculators.filter(row => (category.value === 'all' || row.category === category.value) && (!onlyFavorites.value || favorites.value.includes(row.id)) && `${row.title} ${row.description}`.toLocaleLowerCase('id-ID').includes(search.value.toLocaleLowerCase('id-ID'))));
const groups = computed(() => calculatorCatalog.categories.map(group => ({ ...group, calculators: filtered.value.filter(row => row.category === group.id) })).filter(group => group.calculators.length));
const sources = computed(() => selected.value?.references.map(id => calculatorCatalog.sources[id]).filter(Boolean) ?? []);
const fields = computed(() => selected.value?.fields.filter(field => visibleCalculatorField(field, inputs)) ?? []);
const resultText = computed(() => selected.value && result.value ? calculatorSummary(selected.value, result.value) : '');
function clearInputs() { for (const key of Object.keys(inputs)) delete inputs[key]; }
function open(definition: CalculatorDefinition, record?: CalculationRecord) {
  clearInputs(); Object.assign(inputs, calculatorDefaults(definition), record?.inputs ?? {});
  selected.value = definition; result.value = undefined; error.value = ''; calculated.value = false; information.value = false; draftSaved.value = false;
  if (record) run(false);
}
function toggleFavorite(id: string) {
  favorites.value = favorites.value.includes(id) ? favorites.value.filter(value => value !== id) : [...favorites.value, id];
  try { localStorage.setItem(storageKey('favorites'), JSON.stringify(favorites.value)); } catch { error.value = 'Favorit belum dapat disimpan di browser ini.'; }
}
function run(save = true) {
  if (!selected.value) return;
  calculated.value = true; draftSaved.value = false;
  const output = calculate(selected.value, inputs); error.value = output.error ?? ''; result.value = output.result ?? undefined;
  if (save && result.value) {
    history.value = [{ id: crypto.randomUUID(), calculatorID: selected.value.id, title: selected.value.title, inputs: { ...inputs }, createdAt: new Date().toISOString() }, ...history.value].slice(0, 20);
    try { sessionStorage.setItem(storageKey('history'), JSON.stringify(history.value)); } catch { error.value = 'Hasil tersedia; riwayat belum dapat disimpan.'; }
  }
}
watch(inputs, () => { if (calculated.value) run(false); });
function reset() { if (!selected.value) return; calculated.value = false; result.value = undefined; error.value = ''; draftSaved.value = false; clearInputs(); Object.assign(inputs, calculatorDefaults(selected.value)); }
function clearHistory() {
  if (!window.confirm('Hapus riwayat kalkulator akun ini dari tab browser?')) return;
  history.value = []; try { sessionStorage.removeItem(storageKey('history')); } catch { error.value = 'Riwayat browser belum dapat dihapus.'; }
}
async function copy() { try { await navigator.clipboard.writeText(resultText.value); state.notice = 'Hasil perhitungan disalin'; } catch { error.value = 'Penyalinan belum tersedia. Pilih teks hasil untuk menyalin manual.'; } }
async function share() {
  try { if (navigator.share) await navigator.share({ title: selected.value?.title, text: resultText.value }); else await copy(); }
  catch (cause) { if (!(cause instanceof DOMException && cause.name === 'AbortError')) error.value = 'Hasil belum dapat dibagikan.'; }
}
async function saveDraft() {
  const requestedOwner = owner.value, requestedResult = result.value;
  const amount = result.value?.primaryAmount, definition = selected.value, reference = resultText.value;
  if (!amount || BigInt(amount) <= 0n || !definition || draftSaved.value) return;
  const field = (value: string) => ({ value, confidence: 'high', evidenceSpan: value, sourceType: 'pasted_text' });
  if (await mutate('add_review_item', { id: crypto.randomUUID(), source: 'pasted_text', status: 'pending', amount: field(amount), merchant: field(`Kalkulator: ${definition.title}`), date: field(today()), rawReference: reference, createdAt: new Date().toISOString() }, 'Hasil masuk draft. Saldo belum berubah.') && owner.value === requestedOwner && result.value === requestedResult) draftSaved.value = true;
}
</script>

<template>
  <section class="calculator-page">
    <div class="calculator-intro"><span class="icon-tile mint"><Icon name="calculator" :size="28" /></span><div><h1>Kalkulator</h1><p>Hitung kebutuhan sehari-hari, rencana keuangan, dan kewajiban Islami.</p></div></div>
    <div class="calculator-tools"><label class="calculator-search"><Icon name="search" /><input v-model="search" type="search" placeholder="Cari kalkulator" aria-label="Cari kalkulator"></label><button class="secondary" :aria-pressed="onlyFavorites" @click="onlyFavorites = !onlyFavorites"><Icon name="star" :size="18" />Favorit</button><button class="secondary" @click="historyOpen = true"><Icon name="history" :size="18" />Riwayat</button></div>
    <div class="calculator-categories" role="group" aria-label="Kategori kalkulator"><button :class="{ selected: category === 'all' }" :aria-pressed="category === 'all'" @click="category = 'all'">Semua</button><button v-for="group in calculatorCatalog.categories" :key="group.id" :class="{ selected: category === group.id }" :aria-pressed="category === group.id" @click="category = group.id">{{ group.title }}</button></div>
    <p v-if="!groups.length" class="card muted">{{ onlyFavorites ? 'Belum ada favorit yang cocok. Tandai kalkulator dengan bintang.' : 'Kalkulator tidak ditemukan. Coba kata lain.' }}</p>
    <section v-for="group in groups" :key="group.id" class="calculator-group"><h2>{{ group.title }} <span>{{ group.calculators.length }}</span></h2><div class="calculator-grid"><article v-for="definition in group.calculators" :key="definition.id" class="calculator-tile"><button class="calculator-open" @click="open(definition)"><span class="icon-tile" :class="definition.references.length ? 'mint' : 'sky'"><Icon :name="group.icon" :size="22" /></span><strong>{{ definition.title }}</strong><span>{{ definition.description }}</span><span class="calculator-card-action">Buka kalkulator <Icon name="next" :size="16" /></span></button><button class="icon-button calculator-favorite" :class="{ selected: favorites.includes(definition.id) }" :aria-label="`${favorites.includes(definition.id) ? 'Hapus favorit' : 'Favoritkan'} ${definition.title}`" :aria-pressed="favorites.includes(definition.id)" @click="toggleFavorite(definition.id)"><Icon name="star" :size="18" /></button></article></div></section>
    <Modal v-if="selected" :title="selected.title" class="calculator-dialog" @close="selected = undefined; information = false">
      <p class="muted">{{ selected.description }}</p>
      <div class="button-row"><button class="secondary" :aria-expanded="information" @click="information = !information"><Icon name="info" :size="18" />{{ selected.references.length ? 'Dalil dan metode' : 'Informasi dan rumus' }}</button><button class="text-button" @click="reset">Reset input</button></div>
      <section v-if="information" class="calculator-information"><h3>Metode perhitungan</h3><p>{{ selected.method }}</p><template v-if="sources.length"><h3>Dalil dan rujukan</h3><p class="fine-print">Ringkasan makna, bukan kutipan terjemahan lengkap. Buka sumber untuk membaca teks hadis atau ayat.</p><article v-for="source in sources" :key="source.url"><strong>{{ source.title }}</strong><span class="source-status">{{ source.status }}</span><p>{{ source.meaning }}</p><a :href="source.url" target="_blank" rel="noopener noreferrer">Baca sumber</a></article></template><h3>Ketentuan dan asumsi</h3><p v-for="note in selected.notes" :key="note">{{ note }}</p></section>
      <form class="entry-form calculator-form" @submit.prevent="run()"><div class="form-grid"><label v-for="field in fields" :key="field.key" :class="{ 'calculator-toggle': field.kind === 'toggle' }"><template v-if="field.kind === 'toggle'"><input type="checkbox" :checked="inputs[field.key] === 'true'" @change="inputs[field.key] = ($event.target as HTMLInputElement).checked ? 'true' : 'false'"><span>{{ field.label }}</span></template><template v-else><span>{{ field.label }} <small v-if="field.unit">({{ field.unit }})</small></span><MoneyInput v-if="field.kind === 'money'" v-model="inputs[field.key]" required /><select v-else-if="field.kind === 'choice'" v-model="inputs[field.key]"><option v-for="option in field.options" :key="option.value" :value="option.value">{{ option.label }}</option></select><input v-else-if="field.kind === 'date'" v-model="inputs[field.key]" type="date" required><input v-else v-model="inputs[field.key]" type="text" inputmode="decimal" required placeholder="0" @input="inputs[field.key] = inputs[field.key].replace(',', '.')"></template></label></div><p v-if="error || state.error" class="error-text" role="alert">{{ error || state.error }}</p><button class="primary" type="submit"><Icon name="calculator" />Hitung hasil</button></form>
      <section v-if="result" class="calculator-result" aria-live="polite"><h3>{{ result.headline }}</h3><dl><template v-for="(row, index) in result.rows" :key="index"><dt>{{ row.label }}</dt><dd :class="{ 'result-description': row.kind === 'text' }">{{ calculatorRow(row) }}</dd></template></dl><p v-for="warning in result.warnings" :key="warning" class="callout sun">{{ warning }}</p><details v-if="result.steps.length"><summary>Rincian perhitungan</summary><p v-for="step in result.steps" :key="step">{{ step }}</p><p>{{ selected.method }}</p></details><details v-if="result.schedule.length"><summary>Jadwal / proyeksi {{ result.schedule.length }} periode</summary><div class="calculator-schedule"><article v-for="item in result.schedule" :key="item.period"><strong>{{ item.period }}</strong><span>Rp{{ BigInt(item.amount).toLocaleString('id-ID') }}</span><small>{{ item.detail }}</small></article></div></details><div class="button-row"><button class="secondary" @click="copy"><Icon name="copy" :size="18" />Salin</button><button class="secondary" @click="share"><Icon name="share" :size="18" />Bagikan</button><button v-if="result.primaryAmount && BigInt(result.primaryAmount) > 0n" class="primary" :disabled="state.saving || draftSaved || (!state.online && state.mode !== 'demo')" @click="saveDraft">{{ draftSaved ? 'Sudah masuk draft' : 'Simpan hasil ke draft' }}</button></div><p v-if="result.primaryAmount" class="fine-print">Nominal draft: {{ result.primaryLabel }} — Rp{{ BigInt(result.primaryAmount).toLocaleString('id-ID') }}. Periksa jenis dan akun sebelum mencatat. Saldo berubah setelah konfirmasi.</p></section>
    </Modal>
    <Modal v-if="historyOpen" title="Riwayat kalkulator akun ini" @close="historyOpen = false"><p class="fine-print">Maksimal 20 perhitungan. Riwayat tersimpan per akun selama tab browser ini terbuka.</p><p v-if="!history.length" class="muted">Belum ada perhitungan tersimpan.</p><div class="calculator-history"><button v-for="record in history" :key="record.id" class="secondary" @click="historyOpen = false; open(calculatorCatalog.calculators.find(row => row.id === record.calculatorID)!, record)"><strong>{{ record.title }}</strong><span>{{ new Date(record.createdAt).toLocaleString('id-ID') }}</span></button></div><button v-if="history.length" class="text-button danger-text" @click="clearHistory">Hapus riwayat</button></Modal>
  </section>
</template>

<style scoped>
.calculator-page{display:grid;gap:24px;min-width:0}
.calculator-intro{display:flex;align-items:center;gap:16px;min-width:0}
.calculator-intro>div{min-width:0}
.calculator-intro h1{font-size:28px;margin:0 0 6px;letter-spacing:-.7px}
.calculator-intro p{margin:0;color:var(--muted)}
.calculator-tools{display:flex;align-items:center;gap:10px;flex-wrap:wrap;min-width:0}
.calculator-tools>.secondary{flex:0 0 auto;min-height:48px;white-space:nowrap}
.calculator-search{display:flex;flex-direction:row;align-items:center;gap:10px;flex:1 1 240px;min-width:0;min-height:48px;background:var(--surface);border:1px solid var(--border);border-radius:16px;padding:0 14px}
.calculator-search:focus-within{outline:3px solid var(--focus-ring);outline-offset:3px}
.calculator-search>svg{flex:0 0 20px}
.calculator-search input{flex:1;width:100%;border:0;background:transparent;min-width:0;min-height:46px;padding:0;font-weight:400}
.calculator-search input:focus-visible{outline:none}
.calculator-categories{display:flex;flex-wrap:wrap;align-items:center;gap:8px;min-width:0}
.calculator-categories button{flex:0 0 auto;max-width:100%;white-space:normal;text-align:center;border:1px solid var(--border);border-radius:999px;background:var(--surface);padding:10px 16px;min-height:44px;font-size:14px;line-height:1.4;color:var(--ink)}
.calculator-categories button.selected{background:var(--mint);border-color:var(--primary);color:var(--primary)}
.calculator-group h2{font-size:19px;margin:0 0 14px}
.calculator-group h2 span{font-size:13px;font-weight:500;color:var(--muted);margin-left:8px}
.calculator-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,240px),1fr));gap:14px;min-width:0}
.calculator-tile{min-width:0;position:relative;background:var(--surface);border:1px solid var(--border);border-radius:24px;overflow:hidden}
.calculator-open{display:flex;flex-direction:column;align-items:flex-start;text-align:left;gap:12px;width:100%;height:100%;padding:22px;background:transparent;border:0;color:var(--ink)}
.calculator-open strong{font-size:17px;padding-right:24px}
.calculator-open>span:not(.icon-tile){font-size:14px;line-height:1.6;color:var(--muted)}
.calculator-open .calculator-card-action{margin-top:auto;display:flex;align-items:center;gap:8px;color:var(--primary)!important;font-weight:600}
.calculator-favorite{position:absolute;right:12px;top:14px}
.calculator-favorite.selected{color:var(--primary);background:var(--mint)}
.calculator-information{margin:18px 0;padding:20px;background:var(--canvas);border-radius:20px;line-height:1.7}
.calculator-information h3{margin-top:22px}
.calculator-information h3:first-child{margin-top:0}
.calculator-information article{padding:16px 0}
.source-status{display:block;font-size:12px;color:var(--primary);margin-top:4px}
.calculator-form{margin:22px 0}
.calculator-toggle{display:flex!important;flex-direction:row!important;align-items:flex-start;gap:12px;padding:14px;background:var(--canvas);border-radius:14px}
.calculator-toggle input{width:20px;height:20px;flex-shrink:0;margin-top:2px;accent-color:var(--primary)}
.calculator-result{background:var(--mint);border-radius:22px;padding:22px}
.calculator-result h3{margin:0 0 20px}
.calculator-result dl{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:14px;margin:0 0 20px}
.calculator-result dt{font-size:14px}
.calculator-result dd{margin:0;text-align:right;font-weight:650;font-variant-numeric:tabular-nums;overflow-wrap:anywhere}
.calculator-result dd.result-description{font-size:13px;line-height:1.65;font-weight:500}
.calculator-result details{margin:16px 0}
.calculator-result summary{cursor:pointer;font-weight:600;min-height:44px;align-content:center}
.calculator-schedule{max-height:360px;overflow-y:auto}
.calculator-schedule article{display:grid;grid-template-columns:1fr auto;gap:8px;padding:12px 0}
.calculator-schedule small{grid-column:1/-1;color:var(--muted)}
.calculator-history{display:grid;gap:12px;margin:16px 0}
.calculator-history button{display:flex;flex-direction:column;align-items:flex-start;text-align:left}
.calculator-history span{font-size:12px;color:var(--muted)}
@media(max-width:560px){.calculator-grid{grid-template-columns:1fr}
.calculator-result dl{grid-template-columns:1fr;gap:6px}
.calculator-result dd{text-align:left;margin-bottom:12px}
.calculator-tools>.secondary{flex:1}
.calculator-search{flex-basis:100%}
.calculator-categories button{padding:10px 14px;font-size:13px}
.calculator-intro h1{font-size:25px}}
@media(prefers-reduced-motion:no-preference){.calculator-tile{animation:calculator-reveal .25s ease-out both}@keyframes calculator-reveal{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:translateY(0)}}}
</style>
