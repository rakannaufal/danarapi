import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chartAxisLabel, chartColor, chartPalette, chartPercent } from '../src/report-charts.ts';

test('flow colors keep their meaning when income is zero or reordered', () => {
  assert.equal(chartColor('income'), 'var(--chart-income)');
  assert.equal(chartColor('expense'), 'var(--chart-expense)');
  assert.equal(chartColor('budget:transport'), chartColor('budget:transport'));
  assert.match(chartColor('target:laptop'), /^var\(--chart-[1-6]\)$/);
});
test('chart proportions retain rupiah precision without unsafe number conversion', () => {
  assert.equal(chartPercent('5000', '20000'), 25);
  assert.equal(chartPercent('3000000000000000000', '9000000000000000000'), 33.3333);
  assert.equal(chartPercent('0', '0'), 0);
  assert.equal(chartPercent('-1', '100'), 0);
  assert.equal(chartPercent('200', '100'), 100);
});
test('chart axes are localized and respect hidden amounts', () => {
  assert.equal(chartAxisLabel(0n), '0');
  assert.equal(chartAxisLabel(12500n), '12,5 ribu');
  assert.equal(chartAxisLabel(2000000n), '2 juta');
  assert.equal(chartAxisLabel(9000000000000000000n, true), '•••');
});
test('visible categories have distinct colors shared across charts regardless of order', () => {
  const identifiers = ['food', 'transport', 'household', 'goal:laptop', 'medical', 'shopping'];
  const palette = chartPalette(identifiers);
  assert.equal(new Set(palette.values()).size, 6);
  assert.deepEqual(palette, chartPalette([...identifiers].reverse()));
  assert.deepEqual(chartPalette(['food', 'category:food']), chartPalette(['food']));
});
