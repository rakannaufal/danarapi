import assert from 'node:assert/strict';
import test from 'node:test';
import { hasCompletedOnboarding, saveOnboardingCompletion } from '../src/onboarding.ts';

test('onboarding completion belongs to each account, not the device', () => {
  const values = new Map<string, string>([['onboardingCompleted', 'true']]);
  const storage = { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => { values.set(key, value); } };
  assert.equal(hasCompletedOnboarding(storage, 'first'), false);
  saveOnboardingCompletion(storage, 'first');
  assert.equal(hasCompletedOnboarding(storage, 'first'), true);
  assert.equal(hasCompletedOnboarding(storage, 'second'), false);
  saveOnboardingCompletion(storage, 'second');
  assert.equal(hasCompletedOnboarding(storage, 'first'), true);
  assert.equal(hasCompletedOnboarding(storage, 'second'), true);
});
