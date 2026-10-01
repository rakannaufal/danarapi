import test from 'node:test';
import assert from 'node:assert/strict';
import { moneyDigits, formatMoneyInput, moneyCaret, separatorDeletion } from '../src/money-input.ts';

test('rupiah groups display without changing canonical money', () => {
  for (const [raw, display] of [['', ''], ['0', '0'], ['5000', '5.000'], ['500000', '500.000'], ['999999999999', '999.999.999.999']]) {
    assert.equal(formatMoneyInput(raw), display);
    assert.equal(moneyDigits(display!), raw);
  }
  assert.equal(formatMoneyInput(null), '');
  assert.equal(formatMoneyInput(75000), '75.000');
  assert.equal(moneyDigits('Rp 005.000'), '5000');
  assert.equal(moneyDigits('000'), '0');
  assert.equal(moneyDigits('1234567890123'), '123456789012');
});

test('negative rounding and transient sign remain editable', () => {
  assert.equal(formatMoneyInput('-5000', true), '-5.000');
  assert.equal(moneyDigits('-5.000', true), '-5000');
  assert.equal(formatMoneyInput('-', true), '-');
  assert.equal(formatMoneyInput('-0', true), '0');
  assert.equal(formatMoneyInput('-5000'), '5.000');
});

test('caret follows digits during insertion, replacement, deletion', () => {
  assert.equal(moneyCaret('5000', 4, '5.000'), 5);
  assert.equal(moneyCaret('51.000', 2, '51.000'), 2);
  assert.equal(moneyCaret('1.2345', 6, '12.345'), 6);
  assert.equal(moneyCaret('-5000', 2, '-5.000'), 2);
  assert.equal(moneyCaret('', 0, ''), 0);
  assert.deepEqual(separatorDeletion('12.345', 3, 3, 'deleteContentBackward'), [1, 3]);
  assert.deepEqual(separatorDeletion('12.345', 2, 2, 'deleteContentForward'), [2, 4]);
  assert.deepEqual(separatorDeletion('12.345', 1, 4, 'deleteContentBackward'), [1, 4]);
});
