import catalogJSON from '../../../contracts/calculators/catalog.json';
import '../../../contracts/calculators/engine.js';

export interface CalculatorField {
  key: string; label: string; kind: string; default: string; min?: string; max?: string; unit?: string;
  options?: { value: string; label: string }[]; visible?: Record<string, string | string[]>;
}
export interface CalculatorDefinition {
  id: string; title: string; category: string; description: string; method: string;
  fields: CalculatorField[]; notes: string[]; references: string[];
}
export interface CalculatorSource { title: string; status: string; url: string; meaning: string }
export interface CalculatorResult {
  calculatorID: string; headline: string; status: string; primaryAmount: string | null; primaryLabel: string | null;
  rows: { label: string; value: string; kind: string; unit: string }[];
  warnings: string[]; steps: string[]; schedule: { period: string; amount: string; detail: string }[];
}
export interface CalculationRecord { id: string; calculatorID: string; title: string; inputs: Record<string, string>; createdAt: string }
export const calculatorCatalog = catalogJSON as {
  version: string; categories: { id: string; title: string; icon: string }[];
  sources: Record<string, CalculatorSource>; calculators: CalculatorDefinition[];
};
export const visibleCalculatorField = (field: CalculatorField, values: Record<string, string>) => globalThis.DanarapiCalculatorEngine.visible(field, values);
export function calculate(definition: CalculatorDefinition, values: Record<string, string>): { result: CalculatorResult | null; error: string | null } {
  return globalThis.DanarapiCalculatorEngine.calculate(calculatorCatalog, definition.id, values) as { result: CalculatorResult | null; error: string | null };
}
export function calculatorDefaults(definition: CalculatorDefinition): Record<string, string> {
  const today = new Intl.DateTimeFormat('sv-SE').format(new Date());
  return Object.fromEntries(definition.fields.map(field => [field.key, field.default === 'today' ? today : field.default]));
}
export function calculatorRow(row: CalculatorResult['rows'][number]): string {
  if (row.kind === 'text') return row.value;
  if (row.kind === 'money') return `Rp${BigInt(row.value).toLocaleString('id-ID')}`;
  const negative = row.value.startsWith('-'), parts = row.value.replace(/^-/, '').split('.');
  const decimals = (parts[1] ?? '').replace(/0+$/, '');
  const value = `${negative ? '-' : ''}${BigInt(parts[0]).toLocaleString('id-ID')}${decimals ? ',' + decimals : ''}`;
  return `${value}${row.kind === 'percent' ? '%' : row.unit ? ` ${row.unit}` : ''}`;
}
export function calculatorSummary(definition: CalculatorDefinition, result: CalculatorResult) {
  return [definition.title, result.headline, ...result.rows.map(row => `${row.label}: ${calculatorRow(row)}`), '', `Metode: ${definition.method}`, ...result.warnings].join('\n');
}
