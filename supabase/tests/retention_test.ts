let handler: (request: Request) => Promise<Response>;
const originalServe = Deno.serve;
(Deno as unknown as { serve: (value: typeof handler) => void }).serve = value => { handler = value; };
const { cleanupReviews } = await import('../functions/review-retention/index.ts');
Deno.serve = originalServe;

function assert(value: unknown): asserts value { if (!value) throw new Error('Retention assertion failed'); }

Deno.test('retention deletes bytes before metadata; missing bytes permit idempotent replay', async () => {
  const calls: string[] = [];
  const result = await cleanupReviews('https://backend.invalid', 'server-only', (async (url, options) => {
    const path = String(url); calls.push(`${(options as RequestInit)?.method} ${path}`);
    if (path.endsWith('claim_expired_reviews')) return Response.json([{ id: 'review', storage_keys: ['owner/file.pdf'] }]);
    if (path.endsWith('finish_expired_review')) return new Response(null, { status: 204 });
    return new Response(null, { status: 404 });
  }) as typeof fetch);
  assert(result.deleted === 1 && result.failed === 0);
  assert(calls[1].startsWith('DELETE ') && calls[2].startsWith('GET ') && calls[3].includes('finish_expired_review'));
});

for (const status of [200, 400, 403, 500]) Deno.test(`retention preserves DB metadata when absence verification returns ${status}`, async () => {
  let finished = false;
  const result = await cleanupReviews('https://backend.invalid', 'server-only', (async (url, options) => {
    const path = String(url);
    if (path.endsWith('claim_expired_reviews')) return Response.json([{ id: 'review', storage_keys: ['owner/file.pdf'] }]);
    if (path.endsWith('finish_expired_review')) { finished = true; return new Response(null, { status: 204 }); }
    return new Response(null, { status: (options as RequestInit)?.method === 'DELETE' ? 200 : status });
  }) as typeof fetch);
  assert(result.failed === 1 && result.deleted === 0 && !finished);
});

Deno.test('retention endpoint denies absent/incorrect secret; correct secret still requires POST', async () => {
  Deno.env.delete('RETENTION_JOB_SECRET');
  assert((await handler(new Request('https://edge.invalid', { method: 'POST' }))).status === 401);
  Deno.env.set('RETENTION_JOB_SECRET', 'short');
  assert((await handler(new Request('https://edge.invalid', { method: 'POST', headers: { authorization: 'Bearer short' } }))).status === 401);
  const secret = 'test-job-secret-long-enough-synthetic-only';
  Deno.env.set('RETENTION_JOB_SECRET', secret);
  assert((await handler(new Request('https://edge.invalid', { method: 'POST', headers: { authorization: 'Bearer wrong' } }))).status === 401);
  assert((await handler(new Request('https://edge.invalid', { headers: { authorization: `Bearer ${secret}` } }))).status === 405);
  Deno.env.delete('RETENTION_JOB_SECRET');
});
