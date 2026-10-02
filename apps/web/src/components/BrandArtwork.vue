<script setup lang="ts">
import { brandAsset } from '../brand.ts';
defineProps<{ name: string }>();
</script>
<template>
  <span class="brand-artwork" aria-hidden="true">
    <img class="brand-light" :src="brandAsset(name, 'light')" width="512" height="512" alt="">
    <img class="brand-dark" :src="brandAsset(name, 'dark')" width="512" height="512" alt="">
  </span>
</template>
