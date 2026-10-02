<script setup lang="ts" generic="Value extends string | number | null | undefined">
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { formatMoneyInput, moneyDigits, moneyCaret, separatorDeletion } from '../money-input.ts';
defineOptions({ inheritAttrs: false });
const props = defineProps<{ modelValue: Value; numeric?: boolean; signed?: boolean }>();
const emit = defineEmits<{ 'update:modelValue': [value: Value]; input: [event: Event] }>();
const display = ref(formatMoneyInput(props.modelValue, props.signed));
const inputElement = ref<HTMLInputElement>();
let resizeObserver: ResizeObserver | undefined;
let textSizeObserver: MutationObserver | undefined;
function fitAmount() {
  const input = inputElement.value;
  if (!input?.closest('.amount-input')) return;
  input.style.fontSize = '';
  const style = getComputedStyle(input);
  const context = document.createElement('canvas').getContext('2d');
  if (!context) return;
  context.font = `${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
  const width = context.measureText(input.value || input.placeholder).width;
  const available = input.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight) - 2;
  if (available > 0 && width > available) input.style.fontSize = `${parseFloat(style.fontSize) * available / width}px`;
}
watch(display, () => { void nextTick(fitAmount); });
onMounted(() => {
  const input = inputElement.value;
  if (!input?.closest('.amount-input')) return;
  resizeObserver = new ResizeObserver(fitAmount);
  resizeObserver.observe(input);
  textSizeObserver = new MutationObserver(() => { void nextTick(fitAmount); });
  textSizeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['style', 'class', 'data-theme'] });
  void document.fonts.ready.then(fitAmount);
  fitAmount();
});
onBeforeUnmount(() => { resizeObserver?.disconnect(); textSizeObserver?.disconnect(); });
watch(() => [props.modelValue, props.signed] as const, () => {
  if (props.numeric && props.signed && props.modelValue === null && display.value === '-') return;
  display.value = formatMoneyInput(props.modelValue, props.signed);
});
function beforeInput(event: Event) {
  const input = event.target as HTMLInputElement;
  const selectionStart = input.selectionStart ?? 0;
  const selectionEnd = input.selectionEnd ?? 0;
  const [start, end] = separatorDeletion(input.value, selectionStart, selectionEnd, (event as InputEvent).inputType);
  if (event.cancelable && (start !== selectionStart || end !== selectionEnd)) {
    event.preventDefault();
    input.value = input.value.slice(0, start) + input.value.slice(end);
    input.setSelectionRange(start, start);
    update(event);
  }
}
function update(event: Event) {
  const input = event.target as HTMLInputElement;
  const text = input.value;
  const formatted = formatMoneyInput(text, props.signed);
  const start = moneyCaret(text, input.selectionStart ?? text.length, formatted);
  const end = moneyCaret(text, input.selectionEnd ?? text.length, formatted);
  const raw = moneyDigits(text, props.signed);
  display.value = formatted;
  input.value = formatted;
  input.setSelectionRange(start, end);
  emit('update:modelValue', (props.numeric ? (raw === '' || raw === '-' ? null : Number(raw)) : raw) as Value);
  emit('input', event);
}
</script>
<template><input ref="inputElement" v-bind="$attrs" type="text" class="money-input" :class="{ 'money-long': display.length > 11 }" :inputmode="signed ? 'text' : 'numeric'" :value="display" :pattern="signed ? '-?[0-9]{1,3}(\\.[0-9]{3})*' : '[0-9]{1,3}(\\.[0-9]{3})*'" @beforeinput="beforeInput" @input="update"></template>
<style scoped>
.money-input{font-variant-numeric:tabular-nums}
.amount-input .money-input.money-long{font-size:clamp(1rem,6vw,2.1333rem)}
</style>
