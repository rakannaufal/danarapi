<script setup lang="ts" generic="Value extends string | number | null | undefined">
import { ref, watch } from 'vue';
import { formatMoneyInput, moneyDigits, moneyCaret, separatorDeletion } from '../money-input.ts';
defineOptions({ inheritAttrs: false });
const props = defineProps<{ modelValue: Value; numeric?: boolean; signed?: boolean }>();
const emit = defineEmits<{ 'update:modelValue': [value: Value]; input: [event: Event] }>();
const display = ref(formatMoneyInput(props.modelValue, props.signed));
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
<template><input v-bind="$attrs" type="text" class="money-input" :class="{ 'money-long': display.length > 11 }" :inputmode="signed ? 'text' : 'numeric'" :value="display" :pattern="signed ? '-?[0-9]{1,3}(\\.[0-9]{3})*' : '[0-9]{1,3}(\\.[0-9]{3})*'" @beforeinput="beforeInput" @input="update"></template>
<style scoped>
.money-input{font-variant-numeric:tabular-nums}
.amount-input .money-input.money-long{font-size:clamp(1rem,6vw,2.1333rem)}
</style>
