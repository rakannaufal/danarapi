<script setup lang="ts">
import { ref, watch, nextTick, onMounted, onBeforeUnmount } from 'vue';
import Icon from './Icon.vue';
const props = defineProps<{ title: string; dirty?: boolean }>();
const emit = defineEmits<{ close: [] }>();
const dialog = ref<HTMLDialogElement>();
const previous = document.activeElement as HTMLElement | null;
function focusContent() { const target = [...(dialog.value?.querySelectorAll<HTMLElement>('.modal-body input:not([type="file"]):not(:disabled), .modal-body select:not(:disabled), .modal-body textarea:not(:disabled), .modal-body button:not(:disabled)') ?? [])].find(element => element.tabIndex >= 0 && element.getClientRects().length > 0); (target ?? dialog.value)?.focus(); }
onMounted(() => { dialog.value?.showModal(); focusContent(); });
watch(() => props.title, () => nextTick(focusContent));
onBeforeUnmount(() => { dialog.value?.close(); previous?.focus(); });
function close() { emit('close'); }
function trapFocus(event: KeyboardEvent) {
  if (event.key !== 'Tab' || !dialog.value) return;
  const controls = [...dialog.value.querySelectorAll<HTMLElement>('button, input, select, textarea, summary, a[href], [tabindex]')].filter(element => element.tabIndex >= 0 && !element.matches(':disabled') && element.getClientRects().length > 0);
  event.preventDefault();
  if (!controls.length) { dialog.value.focus(); return; }
  const currentIndex = controls.indexOf(document.activeElement as HTMLElement);
  const nextIndex = currentIndex < 0 ? (event.shiftKey ? controls.length - 1 : 0) : (currentIndex + (event.shiftKey ? -1 : 1) + controls.length) % controls.length;
  controls[nextIndex]?.focus();
}
</script>
<template><dialog ref="dialog" class="modal" aria-labelledby="modal-title" @keydown="trapFocus" @cancel.prevent="close" @click="($event.target === dialog) && close()"><header class="modal-header"><h2 id="modal-title">{{ title }}</h2><button type="button" class="icon-button" aria-label="Tutup" @click="close"><Icon name="close" /></button></header><div class="modal-body"><slot /></div></dialog></template>
