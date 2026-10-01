import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

test('Vercel builds the web app from the repository root with locked dependencies', async () => {
  const root = JSON.parse(await readFile(new URL('../../vercel.json', import.meta.url), 'utf8'));
  const web = JSON.parse(await readFile(new URL('../../apps/web/vercel.json', import.meta.url), 'utf8'));
  const manifest = JSON.parse(await readFile(new URL('../../package.json', import.meta.url), 'utf8'));
  const lock = JSON.parse(await readFile(new URL('../../apps/web/package-lock.json', import.meta.url), 'utf8'));
  assert.equal(root.framework, 'vite');
  assert.equal(root.installCommand, 'npm ci --prefix apps/web');
  assert.equal(root.buildCommand, 'npm run web:build');
  assert.equal(manifest.scripts['web:build'], 'npm run build --prefix apps/web');
  assert.equal(root.outputDirectory, 'apps/web/dist');
  assert.equal(lock.lockfileVersion, 3);
  assert.deepEqual(root.headers, web.headers);
  assert.deepEqual(root.rewrites, web.rewrites);
  assert.equal(root.env, undefined);
  assert.equal(root.build?.env, undefined);
});
