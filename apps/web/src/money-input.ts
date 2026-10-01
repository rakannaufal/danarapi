export function moneyDigits(value: string, signed = false): string {
  const negative = signed && value.trimStart().startsWith('-');
  const digits = value.replace(/[^0-9]/g, '').replace(/^0+(?=[0-9])/, '').slice(0, 12);
  return `${negative && digits !== '0' ? '-' : ''}${digits}`;
}

export function formatMoneyInput(value: string | number | null | undefined, signed = false): string {
  return moneyDigits(String(value ?? ''), signed).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
}

export function moneyCaret(text: string, position: number, formatted: string): number {
  const count = text.slice(0, position).replace(/[^0-9-]/g, '').length;
  if (!count) return 0;
  let seen = 0;
  for (let index = 0; index < formatted.length; index++) {
    if (/[0-9-]/.test(formatted[index]!) && ++seen === count) return index + 1;
  }
  return formatted.length;
}

export function separatorDeletion(text: string, start: number, end: number, type: string): [number, number] {
  if (start !== end) return [start, end];
  if (type === 'deleteContentBackward' && text[start - 1] === '.') return [Math.max(0, start - 2), start];
  if (type === 'deleteContentForward' && text[start] === '.') return [start, Math.min(text.length, start + 2)];
  return [start, end];
}
