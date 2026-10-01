import type { SavingsGoal } from './domain.ts';

export const budgetPresets = ['Makan', 'Transportasi', 'Rumah', 'Belanja', 'Tagihan', 'Kesehatan', 'Pendidikan', 'Hiburan', 'Keluarga', 'Lainnya'];
export function goalCountdown(goal: SavingsGoal, today: string): string {
  if (BigInt(goal.savedAmount) >= BigInt(goal.targetAmount)) return 'Tercapai';
  if (!goal.targetDate) return 'Tanpa tenggat';
  const days = Math.round((Date.parse(`${goal.targetDate.slice(0, 10)}T00:00:00Z`) - Date.parse(`${today}T00:00:00Z`)) / 86400000);
  return days > 0 ? `${days} hari lagi` : days === 0 ? 'Jatuh tempo hari ini' : `Lewat ${Math.abs(days)} hari`;
}
export function progressPercent(saved: string, target: string): number {
  return BigInt(target) > 0n ? Number(BigInt(saved) * 100n / BigInt(target)) : 0;
}
export function budgetStatus(spent: string, limit: string): 'safe' | 'warning' | 'over' {
  const used = BigInt(spent), maximum = BigInt(limit);
  return used > maximum ? 'over' : used * 10n >= maximum * 7n && maximum > 0n ? 'warning' : 'safe';
}
