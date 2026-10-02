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

for (const consent of [[],[{ granted: false,policy_version: '2026-10-02' }],[{ granted: true,policy_version: 'old' }]]) Deno.test(`scan requires current explicit consent ${JSON.stringify(consent)}`, async () => {
  const beforeFetch = globalThis.fetch;
  const names = ['SUPABASE_URL','SUPABASE_ANON_KEY','SUPABASE_SERVICE_ROLE_KEY'];
  const before = names.map(name => Deno.env.get(name));
  names.forEach((name,index) => Deno.env.set(name,['https://backend.invalid','public-test','server-test'][index]));
  let consentReads = 0;
  globalThis.fetch = (input,init) => {
    const url = new URL(String(input));
    if (url.pathname === '/auth/v1/user') return Promise.resolve(Response.json({ id: 'owner' }));
    assert(url.pathname === '/rest/v1/ai_consents');
    assert(new Headers((init as RequestInit | undefined)?.headers).get('authorization') === 'Bearer owner-session');
    consentReads++; return Promise.resolve(Response.json(consent));
  };
  try {
    const response = await scan(new Request('https://edge.invalid/receipt-scan',{ method: 'POST',headers: { authorization: 'Bearer owner-session','content-type': 'application/json' },body: '{}' }));
    assert(response.status === 403); assert((await response.json()).code === 'AI_CONSENT_REQUIRED'); assert(consentReads === 1);
  } finally { globalThis.fetch = beforeFetch; names.forEach((name,index) => { if (before[index] === undefined) Deno.env.delete(name); else Deno.env.set(name,before[index]!); }); }
});

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

Deno.test('successful cloud scan accepts an empty 204 cache completion response', async () => {
  const beforeFetch = globalThis.fetch;
  const names = ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'GEMINI_API_KEY'];
  const before = names.map(name => Deno.env.get(name));
  const values = ['https://backend.invalid', 'sb_publishable_test', 'server-only-test', 'provider-only-test'];
  names.forEach((name, index) => Deno.env.set(name, values[index]));
  let aiCalls = 0, completions = 0;
  const receipt = { merchant: 'Kafe sintetis', date: '2026-10-01', items: [{ name: 'Kopi', qty: 2, unit_price: 10000, line_total: 20000, note: null }], subtotal: 20000, service_charge: 1000, tax: 2000, discount: 0, rounding: 0, grand_total: 23000, tax_included_in_price: false, unreadable_fields: [] };
  globalThis.fetch = (input, init) => {
    const url = new URL(String(input));
    const headers = new Headers((init as RequestInit | undefined)?.headers);
    if (url.pathname === '/auth/v1/user') return Promise.resolve(Response.json({ id: 'synthetic-user' }));
    if (url.pathname === '/rest/v1/ai_consents') { assert(headers.get('authorization') === 'Bearer synthetic-user-session'); return Promise.resolve(Response.json([{ granted: true, policy_version: '2026-10-02' }])); }
    if (url.pathname.endsWith('/claim_receipt_scan')) { assert(headers.get('authorization') === 'Bearer server-only-test'); return Promise.resolve(Response.json({ state: 'new' })); }
    if (url.pathname.endsWith('/reserve_receipt_scan_call')) return Promise.resolve(Response.json(0));
    if (url.pathname.endsWith('/finish_receipt_scan')) { completions++; return Promise.resolve(new Response(null, { status: 204 })); }
    assert(url.hostname === 'generativelanguage.googleapis.com');
    assert(headers.get('x-goog-api-key') === 'provider-only-test');
    assert(!headers.has('authorization'));
    aiCalls++;
    return Promise.resolve(Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: JSON.stringify(receipt) }] } }] }));
  };
  try {
    const data = btoa(String.fromCharCode(137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0));
    const response = await scan(new Request('https://edge.invalid/functions/v1/receipt-scan', { method: 'POST', headers: { authorization: 'Bearer synthetic-user-session', 'content-type': 'application/json' }, body: JSON.stringify({ images: [{ mimeType: 'image/png', data }] }) }));
    assert(response.status === 200);
    const result = await response.json();
    assert(result.status === 'ok'); assert(result.data.grand_total === 23000);
    assert(aiCalls === 1); assert(completions === 1);
  } finally { globalThis.fetch = beforeFetch; names.forEach((name, index) => { if (before[index] === undefined) Deno.env.delete(name); else Deno.env.set(name, before[index]!); }); }
});
