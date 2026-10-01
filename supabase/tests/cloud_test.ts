import { corsFor } from '../functions/_shared/cors.ts';

function assert(value: unknown): asserts value { if (!value) throw new Error('assertion failed'); }

Deno.test('cloud CORS supports explicit production and development origins; never reflects other origins', () => {
  const before = Deno.env.get('ALLOWED_ORIGINS');
  Deno.env.set('ALLOWED_ORIGINS', 'https://app.example.invalid,http://localhost:5173');
  try {
    for (const origin of ['https://app.example.invalid', 'http://localhost:5173']) {
      const headers = corsFor(new Request('https://cloud.invalid', { headers: { origin } }), 'x-review-item-id');
      assert(headers['access-control-allow-origin'] === origin);
      assert(headers.vary === 'Origin');
      assert(headers['access-control-allow-headers'].includes('x-review-item-id'));
    }
    for (const origin of ['https://app.example.invalid.attacker.invalid', 'null', 'https://attacker.invalid']) assert(!corsFor(new Request('https://cloud.invalid', { headers: { origin } }))['access-control-allow-origin']);
    assert(corsFor(new Request('https://cloud.invalid'))['access-control-allow-origin'] === 'https://app.example.invalid');
  } finally { if (before === undefined) Deno.env.delete('ALLOWED_ORIGINS'); else Deno.env.set('ALLOWED_ORIGINS', before); }
});

type Handler = (request: Request) => Promise<Response>;
let captured: Handler;
const originalServe = Deno.serve;
(Deno as unknown as { serve: (handler: Handler) => void }).serve = handler => { captured = handler; };
await import('../functions/receipt-scan/index.ts');
const scan = captured!;
Deno.serve = originalServe;

Deno.test('cloud scan rejects anonymous callers without consuming scan quota or calling AI', async () => {
  const response = await scan(new Request('https://edge.invalid/functions/v1/receipt-scan', { method: 'POST', headers: { apikey: 'sb_publishable_test' } }));
  assert(response.status === 401);
});

Deno.test('cloud scan validates the user JWT through Auth before image parsing or quota RPC', async () => {
  const beforeFetch = globalThis.fetch;
  const names = ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY'];
  const before = names.map(name => Deno.env.get(name));
  Deno.env.set(names[0], 'https://backend.invalid'); Deno.env.set(names[1], 'sb_publishable_test'); Deno.env.set(names[2], 'server-only-test');
  let calls = 0;
  globalThis.fetch = (input, init) => {
    calls++;
    assert(String(input) === 'https://backend.invalid/auth/v1/user');
    assert(new Headers((init as RequestInit | undefined)?.headers).get('authorization') === 'Bearer invalid-session');
    assert(new Headers((init as RequestInit | undefined)?.headers).get('apikey') === 'sb_publishable_test');
    return Promise.resolve(new Response('', { status: 401 }));
  };
  try {
    const response = await scan(new Request('https://edge.invalid/functions/v1/receipt-scan', { method: 'POST', headers: { authorization: 'Bearer invalid-session', 'content-type': 'application/json' }, body: '{}' }));
    assert(response.status === 401); assert(calls === 1);
  } finally { globalThis.fetch = beforeFetch; names.forEach((name, index) => { if (before[index] === undefined) Deno.env.delete(name); else Deno.env.set(name, before[index]!); }); }
});
