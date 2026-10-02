import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';

const origin = new URL(process.argv[2] ?? 'https://danarapi.vercel.app');
assert.equal(origin.protocol, 'https:');
assert.equal(origin.pathname, '/');
assert.ok(!origin.username && !origin.password && !origin.search && !origin.hash);
const expectedHTML = await readFile(new URL('../apps/web/dist/index.html', import.meta.url), 'utf8');
const scripts = [...expectedHTML.matchAll(/(?:src|href)="(\/(?:assets\/[^"<>]+|theme\.js))"/g)].map(match => match[1]);
assert.ok(scripts.some(path => path.endsWith('.js')));
for (const path of ['/', '/about', '/privacy', '/terms', '/contact', '/faq', '/delete-account', '/hapus-akun']) {
  const response = await fetch(new URL(path, origin), { redirect: 'error', signal: AbortSignal.timeout(20000) });
  assert.equal(response.status, 200, `HTTP ${path}`);
  assert.ok(response.headers.get('content-type')?.includes('text/html'), `MIME ${path}`);
  assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
  assert.ok(response.headers.get('content-security-policy')?.includes("frame-ancestors 'none'"));
  assert.ok(response.headers.get('content-security-policy')?.includes("object-src 'none'"));
  const html = await response.text();
  for (const script of scripts) assert.ok(html.includes(script), `Asset versi lama pada ${path}`);
  assert.ok(html.includes('<html lang="id">'));
  console.log(`OK ${path}: HTTPS, SPA, kebijakan keamanan, versi asset`);
}
const checksum = value => createHash('sha256').update(value).digest('hex');
for (const path of scripts) {
  const response = await fetch(new URL(path, origin), { redirect: 'error', signal: AbortSignal.timeout(20000) });
  assert.equal(response.status, 200, `Asset ${path}`);
  const local = await readFile(new URL(`../apps/web/dist${path}`, import.meta.url));
  assert.equal(checksum(new Uint8Array(await response.arrayBuffer())), checksum(local), `Checksum ${path}`);
  console.log(`OK checksum ${path}`);
}
console.log('Deployment web cocok dengan build lokal. Login Google, akun nyata dan jaringan seluler tidak diuji oleh pemeriksaan ini.');
