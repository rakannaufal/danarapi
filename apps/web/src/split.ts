import { moneyString, parseMoney, type MoneyString } from "./contracts.ts";

export interface EqualParticipant {
  id: string;
  included: boolean;
}

export interface PercentageParticipant {
  id: string;
  basis_points: number;
}

export function splitEqual(totalValue: string, participants: EqualParticipant[]): Record<string, MoneyString> {
  const total = parseMoney(totalValue);
  const included = participants.filter((participant) => participant.included);
  if (participants.length < 2 || participants.length > 20 || included.length === 0) throw new Error("VALIDATION");

  const divisor = BigInt(included.length);
  const base = total / divisor;
  let remainder = total % divisor;
  const result: Record<string, MoneyString> = {};
  for (const participant of participants) {
    if (!participant.included) {
      result[participant.id] = moneyString(0n);
      continue;
    }
    const extra = remainder > 0n ? 1n : 0n;
    result[participant.id] = moneyString(base + extra);
    remainder -= extra;
  }
  return result;
}

export function splitPercentage(totalValue: string, participants: PercentageParticipant[]): Record<string, MoneyString> {
  const total = parseMoney(totalValue);
  if (participants.length < 2 || participants.length > 20) throw new Error("VALIDATION");
  if (participants.some((participant) => !Number.isInteger(participant.basis_points) || participant.basis_points < 0 || participant.basis_points > 10_000)) {
    throw new Error("VALIDATION");
  }
  if (participants.reduce((sum, participant) => sum + participant.basis_points, 0) !== 10_000) throw new Error("VALIDATION");

  const rows = participants.map((participant, index) => {
    const numerator = total * BigInt(participant.basis_points);
    return { id: participant.id, index, amount: numerator / 10_000n, fractional: numerator % 10_000n };
  });
  let remainder = total - rows.reduce((sum, row) => sum + row.amount, 0n);
  const ranked = [...rows].sort((a, b) => a.fractional === b.fractional ? a.index - b.index : a.fractional > b.fractional ? -1 : 1);
  for (let index = 0; remainder > 0n; index += 1, remainder -= 1n) ranked[index].amount += 1n;
  return Object.fromEntries(rows.map((row) => [row.id, moneyString(row.amount)]));
}

