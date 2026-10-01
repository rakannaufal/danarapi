<script setup lang="ts">
import { ref } from 'vue';
import { client, state, startDemo, message } from '../store.ts';
import Icon from './Icon.vue';
import { cloudConfiguration } from '../remote.ts';
import { ensureOAuthProvider } from '../cloud.ts';
import ProviderSignInButton from './ProviderSignInButton.vue';
const busy = ref(''), error = ref('');
async function signIn(provider: 'google') {
  if (!client) { error.value = 'Login belum dikonfigurasi.'; return; }
  sessionStorage.removeItem('danarapi.deletion.owner');
  busy.value = provider; error.value = '';
  try {
    if (!cloudConfiguration) throw new Error('Login belum dikonfigurasi.');
    await ensureOAuthProvider(cloudConfiguration, provider);
    const { error: failure } = await client.auth.signInWithOAuth({ provider, options: { redirectTo: window.location.origin + window.location.pathname } });
    if (failure) throw failure;
  } catch (cause) { error.value = message(cause); busy.value = ''; }
}
</script>
<template>
  <main class="auth-layout">
    <section class="auth-story"><a class="brand" href="#home"><span class="brand-symbol">d.</span> danarapi<span class="brand-dot">.</span></a><div><h1>Catat hari ini.<br><span>Rencanakan esok.</span></h1><p>Keuangan pribadi, lebih sederhana.</p></div><p class="fine-print">Pencatat keuangan. Bukan layanan pembayaran.</p></section>
    <section class="auth-card">
      <h2>Selamat datang</h2><p class="muted">Satu akun untuk semua catatanmu.</p>
      <div class="oauth-actions"><ProviderSignInButton provider="google" :busy="busy === 'google'" :disabled="!!busy || !client" @click="signIn('google')" /></div>
      <p v-if="error || state.error" class="error-text" role="alert">{{ error || state.error }}</p><p v-if="!client" class="fine-print">Login belum tersedia. Coba Demo tanpa akun.</p>
      <div class="divider"><span>atau</span></div><button class="secondary demo-button" :disabled="state.loading || !!busy" @click="startDemo"><Icon name="wallet" /> Coba Demo</button>
    </section>
  </main>
</template>
