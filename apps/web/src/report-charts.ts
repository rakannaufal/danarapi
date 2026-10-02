export function chartColor(identifier: string): string {
  if (identifier === 'income') return 'var(--chart-income)';
  if (identifier === 'expense') return 'var(--chart-expense)';
  let hash = 0;
  for (const character of identifier) hash = (hash * 31 + character.charCodeAt(0)) >>> 0;
  return `var(--chart-${hash % 6 + 1})`;
}

export function chartPercent(amount: string | bigint, total: string | bigint): number {
  const value = BigInt(amount), maximum = BigInt(total);
  if (value <= 0n || maximum <= 0n) return 0;
  return Number((value > maximum ? maximum : value) * 1000000n / maximum) / 10000;
}

export function chartPalette(identifiers: string[]): Map<string, string> {
  const colors = new Map<string, string>(), occupied = new Set<number>();
  for (const identifier of [...new Set(identifiers.map(value => value.replace(/^category:/, '')))].sort()) {
    const color = chartColor(identifier);
    const match = color.match(/--chart-([1-6])/);
    if (!match) { colors.set(identifier, color); continue; }
    let slot = Number(match[1]) - 1;
    if (occupied.size === 6) occupied.clear();
    while (occupied.has(slot)) slot = (slot + 1) % 6;
    occupied.add(slot); colors.set(identifier, `var(--chart-${slot + 1})`);
  }
  return colors;
}

export function chartAxisLabel(amount: bigint, hidden = false): string {
  if (hidden) return '•••';
  const unit = amount >= 1000000000n ? 1000000000n : amount >= 1000000n ? 1000000n : amount >= 1000n ? 1000n : 1n;
  const suffix = unit === 1000000000n ? ' miliar' : unit === 1000000n ? ' juta' : unit === 1000n ? ' ribu' : '';
  return `${(Number(amount * 10n / unit) / 10).toLocaleString('id-ID', { maximumFractionDigits: 1 })}${suffix}`;
}
