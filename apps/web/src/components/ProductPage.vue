<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { productContent, productLinks, fetchProductInfo, type ProductInfo, type SupportTicket } from '../product.ts';
import { state, client, productRequest, message, setAIConsent, aiConsent } from '../store.ts';
import { id } from '../domain.ts';
import Icon from './Icon.vue';

const props = defineProps<{ pageID: string }>();
const emit = defineEmits<{ navigate: [page: string] }>();
const page = computed(() => productContent.pages.find(page => page.id === props.pageID));
const query = ref('');
const selectedTopic = ref('');
const topics = computed(() => [...new Set(productContent.faq.map(answer => answer.topic))].sort((left, right) => left.localeCompare(right, 'id-ID')));
const answers = computed(() => productContent.faq.filter(answer => (!selectedTopic.value || answer.topic === selectedTopic.value) && `${answer.topic} ${answer.question} ${answer.answer}`.toLocaleLowerCase('id-ID').includes(query.value.trim().toLocaleLowerCase('id-ID'))));
const topic = ref('lainnya'), description = ref(''), requestID = ref(''), sending = ref(false), sent = ref(''), error = ref('');
const tickets = ref<SupportTicket[]>([]), info = ref<ProductInfo>();
const acknowledged = ref(false);
let ticketID = id();
const title = computed(() => page.value?.title ?? (props.pageID === 'faq' ? productContent.help.title : props.pageID === 'contact' ? productContent.help.contactTitle : productLinks.find(link => link.id === props.pageID)?.title) ?? 'Bantuan');
async function send() {
  if (description.value.trim().length < 10) { error.value = 'Jelaskan masalah minimal 10 karakter.'; return; }
  if (requestID.value && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(requestID.value)) { error.value = 'ID permintaan harus berupa UUID.'; return; }
  if (!client || state.mode !== 'authenticated') { error.value = 'Masuk untuk mengirim laporan privat.'; return; }
  sending.value = true; error.value = '';
  try {
    await productRequest('create_support_ticket', { id: ticketID, topic: topic.value, description: description.value.trim(), platform: 'web', appVersion: `web-${productContent.version}`, requestID: requestID.value || null });
    sent.value = ticketID; description.value = ''; requestID.value = ''; ticketID = id();
    await readTickets();
  } catch (cause) { error.value = message(cause); }
  finally { sending.value = false; }
}
async function readTickets() {
  if (state.mode !== 'authenticated') { tickets.value = []; return; }
  const result = await productRequest('support'); tickets.value = result.items;
}
watch(() => [props.pageID, state.mode], async () => {
  error.value = ''; sent.value = '';
  query.value = ''; selectedTopic.value = '';
  if (props.pageID === 'contact') {
    try { await readTickets(); } catch (cause) { error.value = message(cause); }
    try { info.value = await fetchProductInfo(); } catch { info.value = undefined; }
  }
  if (props.pageID === 'privacy' && state.mode === 'authenticated') {
    try { const result = await productRequest('consent'); aiConsent.value = result; } catch (cause) { error.value = message(cause); }
  }
}, { immediate: true });
async function acknowledgeRetention() {
  if (!client || sending.value) return;
  sending.value = true; error.value = '';
  try { const result = await client.rpc('acknowledge_retention_policy'); if (result.error) throw result.error; acknowledged.value = true; }
  catch (cause) { error.value = message(cause); }
  finally { sending.value = false; }
}
</script>
<template>
  <article class="product-page" :class="{ 'product-about': pageID === 'about', 'product-faq': pageID === 'faq' }">
    <header class="product-header"><button class="product-wordmark" @click="emit('navigate', 'home')"><Icon name="back" :size="16" />Danarapi</button><h1>{{ title }}</h1><p class="muted">{{ page?.subtitle ?? (pageID === 'faq' ? productContent.help.subtitle : productContent.help.contactIntro) }}</p><small v-if="page && page.id !== 'about'" class="muted">Berlaku {{ productContent.version }} · {{ productContent.owner }}</small></header>
    <template v-if="page">
      <div class="product-section-grid" :class="{ 'about-sections': page.id === 'about' }"><section v-for="section in page.sections" :key="section.title" class="card"><h2>{{ section.title }}</h2><p v-for="paragraph in section.paragraphs" :key="paragraph">{{ paragraph }}</p></section></div>
      <section v-if="page.id === 'about'" class="product-features"><h2>Fitur Danarapi</h2><div class="product-feature-grid"><article v-for="feature in productContent.features" :key="feature.id" class="card product-feature"><span class="icon-tile sky"><Icon :name="feature.id" :size="22" /></span><h3>{{ feature.title }}</h3><p>{{ feature.description }}</p></article></div></section>
      <section v-if="page.id === 'privacy' && state.mode === 'authenticated'" class="card"><h2>Pengiriman struk ke AI</h2><p>{{ aiConsent?.granted && aiConsent.policyVersion === productContent.version ? 'Persetujuan aktif untuk versi kebijakan ini.' : 'Persetujuan diminta sebelum unggahan pertama.' }}</p><button class="secondary" :disabled="sending" @click="sending = true; setAIConsent(false).catch(cause => error = message(cause)).finally(() => sending = false)">Cabut persetujuan AI</button></section>
      <section v-if="page.id === 'privacy' && state.mode === 'authenticated'" class="card"><h2>Penerimaan retensi</h2><button v-if="!acknowledged" class="secondary" :disabled="sending" @click="acknowledgeRetention">Saya sudah membaca kebijakan retensi</button><p v-else role="status">Penerimaan kebijakan tercatat.</p></section>
      <p v-if="page.id === 'about'" class="fine-print">Web · {{ productContent.version }}</p>
    </template>
    <template v-else-if="pageID === 'faq'">
      <section class="card help-search-panel"><label class="product-search">{{ productContent.help.searchPlaceholder }}<span class="search-field"><Icon name="search" :size="19" /><input v-model="query" type="search" placeholder="Saldo, scan, target…"></span></label><div class="help-topics" role="group" aria-label="Topik bantuan"><button class="help-topic" :aria-pressed="!selectedTopic" @click="selectedTopic = ''">{{ productContent.help.allTopics }}</button><button v-for="item in topics" :key="item" class="help-topic" :aria-pressed="selectedTopic === item" @click="selectedTopic = item">{{ item }}</button></div></section>
      <section v-if="!query.trim() && !selectedTopic" class="help-getting-started"><h2>{{ productContent.help.gettingStartedTitle }}</h2><div class="help-guide-grid"><article v-for="(step, index) in productContent.help.gettingStarted" :key="step.id" class="card help-guide"><span class="help-step">{{ index + 1 }}</span><h3>{{ step.title }}</h3><p>{{ step.description }}</p></article></div></section>
      <div class="help-answers"><section v-if="!answers.length" class="card chart-empty"><Icon name="search" :size="28" /><h2>{{ productContent.help.emptyTitle }}</h2><p>{{ productContent.help.emptyMessage }}</p><button class="secondary" @click="emit('navigate', 'contact')">Kontak</button></section><details v-for="answer in answers" :key="answer.id" class="card product-answer"><summary><span><small>{{ answer.topic }}</small>{{ answer.question }}</span><Icon name="next" :size="18" /></summary><p>{{ answer.answer }}</p></details></div>
    </template>
    <template v-else-if="pageID === 'contact'">
      <section class="card">
        <h2>Lapor masalah</h2><p>{{ productContent.help.contactIntro }}</p><p class="muted">{{ productContent.help.supportPrivacy }}</p>
        <a v-if="info?.supportEmail" class="secondary" :href="`mailto:${info.supportEmail}`"><Icon name="help" />{{ info.supportEmail }}</a>
        <form v-if="state.mode === 'authenticated'" class="entry-form" @submit.prevent="send">
          <label>Topik<select v-model="topic"><option v-for="item in productContent.supportTopics" :key="item.id" :value="item.id">{{ item.title }}</option></select></label>
          <label>Pesan<textarea v-model="description" required minlength="10" maxlength="4000" rows="5" :placeholder="productContent.help.messagePlaceholder"></textarea></label>
          <label><span class="field-label">{{ productContent.help.requestLabel }} <span class="optional">opsional</span></span><input v-model="requestID" maxlength="36" autocomplete="off"></label>
          <button class="primary" :disabled="sending || !state.online || description.trim().length < 10">{{ sending ? 'Mengirim…' : productContent.help.submitLabel }}</button>
        </form>
        <template v-else><p>{{ productContent.help.signInMessage }}</p><button class="primary" @click="emit('navigate', 'home')">Masuk</button></template>
        <p v-if="sent" role="status">Laporan tersimpan. ID: {{ sent }}</p>
      </section>
      <section v-if="tickets.length" class="card"><h2>Laporan Anda</h2><details v-for="ticket in tickets" :key="ticket.id" class="product-ticket"><summary>{{ ticket.topic }} · {{ ticket.status === 'resolved' ? 'Selesai' : ticket.status === 'in_progress' ? 'Ditangani' : 'Menunggu' }} · {{ new Date(ticket.createdAt).toLocaleDateString('id-ID') }}</summary><p>{{ ticket.description }}</p><p v-if="ticket.reply"><strong>Balasan</strong><br>{{ ticket.reply }}</p><small class="muted">{{ ticket.id }}</small></details></section>
    </template>
    <p v-if="error" class="error-text" role="alert">{{ error }}</p>
  </article>
</template>
