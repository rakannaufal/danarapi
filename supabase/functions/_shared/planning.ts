export interface Allocation { id: string; name: string; amount: string }
export function allocationBreakdown(
  categories: { categoryID: string; amount: string }[],
  contributions: { categoryID: string; goalID: string; amount: string }[],
  goals: { id: string; name: string }[],
  names: { id: string; name: string }[],
  budgetCategories: Set<string>,
): Allocation[] {
  const remaining = new Map(categories.map(row => [row.categoryID, BigInt(row.amount)]));
  const allocated = new Map<string, Allocation>();
  for (const row of contributions) {
    const available = remaining.get(row.categoryID) ?? 0n;
    const amount = BigInt(row.amount);
    if (amount <= 0n || amount > available) throw new Error('Alokasi target tidak sesuai pengeluaran.');
    remaining.set(row.categoryID, available - amount);
    const existing = allocated.get(row.goalID);
    allocated.set(row.goalID, { id: `goal:${row.goalID}`, name: `Target · ${goals.find(goal => goal.id === row.goalID)?.name ?? 'Target'}`, amount: (BigInt(existing?.amount ?? '0') + amount).toString() });
  }
  const result = [...allocated.values()];
  for (const [categoryID, amount] of remaining) {
    if (amount <= 0n) continue;
    const name = names.find(row => row.id === categoryID)?.name ?? 'Kategori';
    result.push({ id: `category:${categoryID}`, name: budgetCategories.has(categoryID) ? `Anggaran · ${name}` : name, amount: amount.toString() });
  }
  return result.sort((left, right) => BigInt(left.amount) === BigInt(right.amount) ? left.id.localeCompare(right.id) : BigInt(left.amount) > BigInt(right.amount) ? -1 : 1);
}
