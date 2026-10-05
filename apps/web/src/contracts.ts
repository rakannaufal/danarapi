export const SCHEMA_VERSION = "1.0.0" as const;
export const MAX_IDR = 999_999_999_999n;

export function parseSignedMoney(value: unknown): bigint {
  if (typeof value !== 'string' || !/^-?(0|[1-9][0-9]{0,11})$/.test(value)) throw new Error('Saldo harus berupa Rupiah bulat.');
  const amount = BigInt(value);
  if (amount < -MAX_IDR || amount > MAX_IDR) throw new Error('Saldo melebihi batas nominal.');
  return amount;
}

export type MoneyString = string & { readonly __moneyString: unique symbol };

export function parseMoney(value: unknown, allowZero = false): bigint {
  if (typeof value !== "string" || !/^(0|[1-9][0-9]{0,11})$/.test(value)) {
    throw new Error("VALIDATION");
  }
  const amount = BigInt(value);
  if (amount > MAX_IDR || (!allowZero && amount === 0n)) {
    throw new Error("VALIDATION");
  }
  return amount;
}

export function moneyString(value: bigint): MoneyString {
  if (value < 0n || value > MAX_IDR) throw new Error("VALIDATION");
  return value.toString() as MoneyString;
}

export interface ApiError {
  code: string;
  message: string;
  request_id: string;
  details: Record<string, unknown>;
}
