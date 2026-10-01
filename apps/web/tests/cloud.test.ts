import assert from 'node:assert/strict';
import { test } from 'node:test';
import { cloudProject, ensureOAuthProvider, resolveCloudConfiguration } from '../src/cloud.ts';

test('web and iOS ship the same HTTPS cloud project and public key', async () => {
  const { readFile } = await import('node:fs/promises');
  const native = await readFile(new URL('../../ios/Configuration/Base.xcconfig', import.meta.url), 'utf8');
  assert.deepEqual(resolveCloudConfiguration({}), cloudProject);
  assert.ok(native.includes(cloudProject.url.replace('https://', 'https:/$()/')));
  assert.ok(native.includes(cloudProject.key));
});

test('public key aliases work; partial, secret and invalid configuration fails closed', () => {
  assert.deepEqual(resolveCloudConfiguration({ VITE_SUPABASE_URL: cloudProject.url, VITE_SUPABASE_ANON_KEY: cloudProject.key }), cloudProject);
  assert.deepEqual(resolveCloudConfiguration({ VITE_SUPABASE_URL: cloudProject.url, VITE_SUPABASE_PUBLISHABLE_KEY: cloudProject.key }), cloudProject);
  for (const env of [
    { VITE_SUPABASE_URL: '' },
    { VITE_SUPABASE_URL: 'https://other.invalid' },
    { VITE_SUPABASE_ANON_KEY: cloudProject.key },
    { VITE_SUPABASE_URL: cloudProject.url, VITE_SUPABASE_ANON_KEY: 'sb_secret_private' },
    { VITE_SUPABASE_URL: 'http://remote.invalid', VITE_SUPABASE_ANON_KEY: cloudProject.key },
    { VITE_SUPABASE_URL: `${cloudProject.url}/unexpected`, VITE_SUPABASE_ANON_KEY: cloudProject.key },
    { VITE_SUPABASE_URL: 'https://user:password@example.invalid', VITE_SUPABASE_ANON_KEY: cloudProject.key },
    { VITE_SUPABASE_URL: cloudProject.url, VITE_SUPABASE_ANON_KEY: `eyJ.${btoa(JSON.stringify({ role: 'service_role' }))}.test` },
  ]) assert.equal(resolveCloudConfiguration(env), null);
});

test('OAuth checks provider availability with apikey, never a public-key bearer token', async () => {
  await ensureOAuthProvider(cloudProject, 'google', (async (url, init) => {
    assert.equal(url, `${cloudProject.url}/auth/v1/settings`);
    assert.equal(new Headers(init?.headers).get('apikey'), cloudProject.key);
    assert.equal(new Headers(init?.headers).get('authorization'), null);
    return Response.json({ external: { google: true } });
  }) as typeof fetch);
  await assert.rejects(ensureOAuthProvider(cloudProject, 'google', (async () => Response.json({ external: { google: false } })) as typeof fetch), /Google belum diaktifkan/);
  await assert.rejects(ensureOAuthProvider(cloudProject, 'apple' as 'google', (async () => { assert.fail('Unsupported provider must not contact Auth'); }) as typeof fetch), /Provider login tidak valid/);
  await assert.rejects(ensureOAuthProvider(cloudProject, 'google', (async () => new Response('', { status: 503 })) as typeof fetch), /belum tersedia/);
});
