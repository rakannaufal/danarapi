import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { cloudProject } from '../../apps/web/src/cloud.ts';

test('Gitleaks keeps default detectors and exempts only the known public client key', async () => {
  const configuration = await readFile(new URL('../../.gitleaks.toml', import.meta.url), 'utf8');
  assert.match(configuration, /useDefault = true/);
  assert.match(configuration, /regexTarget = "secret"/);
  const pattern = configuration.match(/^regexes = \['''(.+)'''\]$/m)?.[1];
  assert.ok(pattern);
  const allowed = new RegExp(pattern);
  assert.equal(allowed.test(cloudProject.key), true);
  assert.equal(allowed.test(`${cloudProject.key}-extra`), false);
  assert.equal(allowed.test(cloudProject.key.replace('sb_publishable_', 'sb_secret_')), false);
  assert.equal(allowed.test('SUPABASE_SERVICE_ROLE_KEY'), false);
  assert.doesNotMatch(configuration, /^\s*(?:paths|stopwords|commits)\s*=/m);
});
