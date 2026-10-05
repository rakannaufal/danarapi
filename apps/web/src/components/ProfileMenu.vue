<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue';
import { state } from '../store.ts';
import Icon from './Icon.vue';

defineEmits<{ settings: []; logout: [] }>();
const expanded = ref(false);
const container = ref<HTMLElement>();
const trigger = ref<HTMLButtonElement>();
const menu = ref<HTMLElement>();

async function openMenu(last = false) {
  expanded.value = true;
  await nextTick();
  const items = menu.value?.querySelectorAll<HTMLButtonElement>('[role="menuitem"]:not(:disabled)');
  items?.[last ? items.length - 1 : 0]?.focus();
}
function closeMenu(restoreFocus = false) {
  expanded.value = false;
  if (restoreFocus) trigger.value?.focus();
}
function triggerKey(event: KeyboardEvent) {
  if (!['ArrowDown', 'ArrowUp'].includes(event.key)) return;
  event.preventDefault();
  void openMenu(event.key === 'ArrowUp');
}
function menuKey(event: KeyboardEvent) {
  const items = Array.from(menu.value?.querySelectorAll<HTMLButtonElement>('[role="menuitem"]:not(:disabled)') ?? []);
  const index = items.indexOf(document.activeElement as HTMLButtonElement);
  if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
    event.preventDefault();
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? items.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
    items[next]?.focus();
  } else if (event.key === 'Tab') closeMenu(true);
}
function outsidePointer(event: PointerEvent) {
  if (event.target instanceof Node && !container.value?.contains(event.target)) closeMenu();
}
function escapeKey(event: KeyboardEvent) {
  if (expanded.value && event.key === 'Escape') {
    event.preventDefault();
    closeMenu(true);
  }
}
function focusLeft(event: FocusEvent) {
  if (event.relatedTarget instanceof Node && !container.value?.contains(event.relatedTarget)) closeMenu();
}
onMounted(() => {
  document.addEventListener('pointerdown', outsidePointer);
  document.addEventListener('keydown', escapeKey);
});
onBeforeUnmount(() => {
  document.removeEventListener('pointerdown', outsidePointer);
  document.removeEventListener('keydown', escapeKey);
});
</script>

<template>
  <div ref="container" class="profile-menu" @focusout="focusLeft">
    <button ref="trigger" class="profile-button" aria-label="Menu akun" aria-haspopup="menu" :aria-expanded="expanded" aria-controls="profile-actions" @click="expanded ? closeMenu() : openMenu()" @keydown="triggerKey">
      <span class="avatar mint">{{ state.mode === 'demo' ? 'D' : state.email.charAt(0).toUpperCase() }}</span>
      <span class="profile-name"><strong>{{ state.mode === 'demo' ? 'Teman Demo' : state.email }}</strong></span>
      <Icon name="more" />
    </button>
    <div v-if="expanded" id="profile-actions" ref="menu" class="profile-popup" role="menu" aria-label="Menu akun" @keydown="menuKey">
      <button role="menuitem" @click="closeMenu(); $emit('settings')"><Icon name="settings" :size="18" />Pengaturan</button>
      <button role="menuitem" class="profile-logout" :disabled="state.saving" @click="closeMenu(); $emit('logout')"><Icon name="logout" :size="18" />Keluar</button>
    </div>
  </div>
</template>
