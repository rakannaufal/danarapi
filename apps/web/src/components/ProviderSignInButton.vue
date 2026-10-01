<script setup lang="ts">
defineProps<{ provider: 'google'; busy?: boolean; disabled?: boolean }>();
</script>

<template>
  <button type="button" class="provider-sign-in" :class="`provider-sign-in--${provider}`" :disabled="disabled || busy" :aria-busy="busy || undefined" aria-label="Lanjutkan dengan Google">
    <img class="provider-logo" src="/brand/google-sign-in.png" alt="" aria-hidden="true" width="22" height="22">
    <span class="provider-label">{{ busy ? 'Menghubungkan…' : 'Lanjutkan dengan Google' }}</span>
    <span class="provider-status" aria-hidden="true"><span v-if="busy" class="provider-spinner"></span></span>
  </button>
</template>
