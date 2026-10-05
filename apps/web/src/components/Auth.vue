<script setup lang="ts">
import { ref } from 'vue';
import { client, state, message } from '../store.ts';
import { cloudConfiguration } from '../remote.ts';
import { ensureOAuthProvider } from '../cloud.ts';
import ProviderSignInButton from './ProviderSignInButton.vue';
import BrandIdentity from './BrandIdentity.vue';
import BrandArtwork from './BrandArtwork.vue';
import { welcomeContent } from '../brand.ts';
const busy = ref(''), error = ref('');
async function signIn(provider: 'google') {
  if (busy.value) return;
  if (!client) { error.value = 'Login belum dikonfigurasi.'; return; }
  sessionStorage.removeItem('danarapi.deletion.owner');
  busy.value = provider; error.value = '';
  try {
    if (!cloudConfiguration) throw new Error('Login belum dikonfigurasi.');
    await ensureOAuthProvider(cloudConfiguration, provider);
    const { error: failure } = await client.auth.signInWithOAuth({ provider, options: { redirectTo: window.location.origin + window.location.pathname, queryParams: { prompt: 'select_account' } } });
    if (failure) throw failure;
  } catch (cause) { error.value = message(cause); } finally { busy.value = ''; }
}
</script>
<template>
  <div class="auth-screen">
  <main class="auth-layout">
    <section class="auth-story"><a class="brand" href="#home" aria-label="Danarapi"><BrandIdentity /></a><div><h1>{{ welcomeContent.headline }}</h1><p>{{ welcomeContent.subtitle }}</p></div><BrandArtwork class="auth-illustration" name="onboarding_2" /><p class="fine-print">{{ welcomeContent.disclaimer }}</p></section>
    <section class="auth-card">
      <h2>{{ welcomeContent.signInTitle }}</h2><p class="muted">{{ welcomeContent.signInSubtitle }}</p>
      <div class="oauth-actions"><ProviderSignInButton provider="google" :busy="busy === 'google'" :disabled="!!busy || !client" @click="signIn('google')" /></div>
      <p v-if="error || state.error" class="error-text" role="alert">{{ error || state.error }}</p><p v-if="!client" class="fine-print">Login belum tersedia. Coba lagi nanti.</p>
    </section>
  </main>
  </div>
</template>
