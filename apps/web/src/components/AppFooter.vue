<script setup lang="ts">
import { productLinks } from '../product.ts';

defineProps<{ page: string }>();
const emit = defineEmits<{ navigate: [page: string] }>();
</script>

<template>
  <footer class="site-footer">
    <div class="site-footer-inner">
      <div class="site-footer-brand"><strong>Danarapi</strong><span>Keuangan rapi, langkah lebih tenang.</span></div>
      <div class="site-footer-help">
        <h2>Tentang & bantuan</h2>
        <nav aria-label="Tentang dan bantuan">
          <a v-for="link in productLinks" :key="link.id" :href="`#${link.id}`" :aria-current="page === link.id ? 'page' : undefined" @click.prevent="emit('navigate', link.id)">{{ link.title }}</a>
        </nav>
      </div>
    </div>
  </footer>
</template>
