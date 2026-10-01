import { parseMoney } from "./contracts.ts";

export type ReceiptLine = { id: string; name: string; quantity: number; unitPrice: string; allocations: { memberID: string; quantity: number }[] };
export type ItemSplit = { items: ReceiptLine[]; tax: string; service: string; discount: string; rounding?: string; settings?: { serviceRate: number; taxRate: number; taxOnService: boolean; taxIncluded?: boolean } };

export function calculateReceipt(draft: ItemSplit, memberIDs: string[]) {
  const settings = draft.settings!;
  if (!settings || typeof settings.taxOnService !== 'boolean' || (settings.taxIncluded !== undefined && typeof settings.taxIncluded !== 'boolean') || memberIDs.length < 1 || memberIDs.length > 20 || new Set(memberIDs).size !== memberIDs.length || memberIDs.some(id => typeof id !== 'string' || !id) || [settings.serviceRate, settings.taxRate].some(rate => !Number.isFinite(rate) || rate < 0 || rate > 100 || Math.abs(rate * 100 - Math.round(rate * 100)) > 1e-8)) throw new Error('VALIDATION');
  const denominator = 232792560n;
  const bases = memberIDs.map(() => 0n);
  const unassigned: string[] = [];
  for (const item of draft.items) {
    if (!Number.isInteger(item.quantity) || item.quantity < 0 || item.quantity > 999999) throw new Error('VALIDATION');
    const total = parseMoney(item.unitPrice || '0', true) * BigInt(item.quantity);
    const owners = memberIDs.filter(memberID => item.allocations.some(entry => entry.memberID === memberID && entry.quantity > 0));
    if (!owners.length) { if (total > 0n) unassigned.push(item.name || '(tanpa nama)'); continue; }
    for (const owner of owners) bases[memberIDs.indexOf(owner)]! += total * (denominator / BigInt(owners.length));
  }
  function distribute(values: bigint[], divisor: bigint) {
    const sum = values.reduce((total, value) => total + value, 0n);
    const target = (sum * 2n + divisor) / (divisor * 2n);
    const floors = values.map(value => value / divisor);
    const left = Number(target - floors.reduce((total, value) => total + value, 0n));
    const order = values.map((value, index) => ({ index, remainder: value % divisor })).sort((first, second) => first.remainder === second.remainder ? first.index - second.index : first.remainder > second.remainder ? -1 : 1);
    for (const entry of order.slice(0, left)) floors[entry.index]! += 1n;
    return floors;
  }
  const baseSum = bases.reduce((sum, value) => sum + value, 0n);
  if (baseSum > 999999999999n * denominator) throw new Error('VALIDATION');
  const discountValue = parseMoney(draft.discount || '0', true);
  if (baseSum > 0n && discountValue * denominator > baseSum) throw new Error('VALIDATION');
  const roundingText = draft.rounding || '0';
  if (!/^-?(0|[1-9][0-9]{0,11})$/.test(roundingText)) throw new Error('VALIDATION');
  const roundingValue = BigInt(roundingText);
  const ratioDivisor = baseSum || denominator;
  const discounted = bases.map(value => value * (baseSum > 0n ? baseSum - discountValue * denominator : ratioDivisor));
  const serviceRate = BigInt(Math.round(settings.serviceRate * 100));
  const taxRate = BigInt(Math.round(settings.taxRate * 100));
  const subtotal = distribute(bases, denominator);
  const discount = distribute(bases.map(value => value * discountValue), ratioDivisor);
  const service = distribute(discounted.map(value => settings.taxIncluded ? 0n : value * serviceRate), denominator * ratioDivisor * 10000n);
  const tax = distribute(discounted.map(value => settings.taxIncluded ? 0n : value * (settings.taxOnService ? 10000n + serviceRate : 10000n) * taxRate), denominator * ratioDivisor * 100000000n);
  const rounding = distribute(bases.map(value => value * (roundingValue < 0n ? -roundingValue : roundingValue)), ratioDivisor).map(value => roundingValue < 0n ? -value : value);
  const rows = memberIDs.map((id, index) => ({ id, subtotal: subtotal[index]!.toString(), discount: discount[index]!.toString(), service: service[index]!.toString(), tax: tax[index]!.toString(), rounding: rounding[index]!.toString(), total: (subtotal[index]! - discount[index]! + service[index]! + tax[index]! + rounding[index]!).toString() }));
  const total = rows.reduce((sum, row) => sum + BigInt(row.total), 0n);
  if (total < 0n || total > 999999999999n || rows.some(row => BigInt(row.total) < 0n)) throw new Error('VALIDATION');
  return { rows, unassigned, total: total.toString(), shares: Object.fromEntries(rows.map(row => [row.id, row.total])) };
}

export function splitItems(draft: ItemSplit, memberIDs: string[]) {
  const maximum = 999999999999n;
  const invalid = () => { throw new Error("VALIDATION"); };
  if (memberIDs.length < 2 || memberIDs.length > 20 || new Set(memberIDs).size !== memberIDs.length || memberIDs.some((id) => typeof id !== "string" || !id) || !draft.items.length || draft.items.length > 100 || new Set(draft.items.map((row) => row.id)).size !== draft.items.length) invalid();
  if (draft.settings) {
    if (draft.items.some(row => !row.id || !row.name.trim() || row.name.length > 160 || row.allocations.some(entry => !memberIDs.includes(entry.memberID) || entry.quantity !== 1) || new Set(row.allocations.map(entry => entry.memberID)).size !== row.allocations.length)) invalid();
    const result = calculateReceipt(draft, memberIDs);
    if (result.unassigned.length || result.total === '0') invalid();
    return { total: result.total, shares: result.shares };
  }
  const bases = new Map(memberIDs.map((id) => [id, 0n]));
  let subtotal = 0n;
  for (const row of draft.items) {
    if (typeof row.id !== "string" || !row.id || typeof row.name !== "string" || !row.name.trim() || row.name.length > 160 || !Number.isInteger(row.quantity) || row.quantity < 1 || row.quantity > 999999 || new Set(row.allocations.map((entry) => entry.memberID)).size !== row.allocations.length) invalid();
    const price = parseMoney(row.unitPrice);
    subtotal += price * BigInt(row.quantity);
    if (subtotal > maximum) invalid();
    let assigned = 0;
    for (const entry of row.allocations) {
      if (!bases.has(entry.memberID) || !Number.isInteger(entry.quantity) || entry.quantity < 0 || entry.quantity > 999999) invalid();
      assigned += entry.quantity;
      bases.set(entry.memberID, bases.get(entry.memberID)! + price * BigInt(entry.quantity));
    }
    if (assigned !== row.quantity) invalid();
  }
  const gross = subtotal + parseMoney(draft.tax, true) + parseMoney(draft.service, true);
  const discount = parseMoney(draft.discount, true);
  if (gross > maximum || discount >= gross) invalid();
  const total = gross - discount;
  const rows = memberIDs.map((id, order) => { const numerator = bases.get(id)! * total; return { id, order, amount: numerator / subtotal, remainder: numerator % subtotal }; });
  const remaining = Number(total - rows.reduce((sum, row) => sum + row.amount, 0n));
  const ordered = [...rows].sort((first, second) => first.remainder === second.remainder ? first.order - second.order : first.remainder > second.remainder ? -1 : 1);
  for (const row of ordered.slice(0, remaining)) row.amount += 1n;
  return { total: total.toString(), shares: Object.fromEntries(rows.map((row) => [row.id, row.amount.toString()])) };
}
