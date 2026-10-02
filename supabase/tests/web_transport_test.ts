type Handler = (request: Request) => Promise<Response>;
let captured: Handler;
const originalServe = Deno.serve;
(Deno as unknown as { serve: (handler: Handler) => void }).serve = (handler) => { captured = handler; };
await import('../functions/ledger/index.ts');
const ledger = captured!;
await import('../functions/ios-data/index.ts');
const data = captured!;
await import('../functions/export-data/index.ts');
const exportData = captured!;
Deno.serve = originalServe;
Deno.env.set('SUPABASE_URL', 'https://backend.invalid');
Deno.env.set('SUPABASE_ANON_KEY', 'test-public-key');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'test-server-only-key');

function assert(value: unknown, message = 'assertion failed'): asserts value { if (!value) throw new Error(message); }
for (const owned of [true, false]) Deno.test(`posted attachment validates owner before Storage (${owned})`, async () => {
  const target = 'ca000000-0000-4000-8000-000000000001';
  await mocked(async calls => {
    const response = await data(new Request('https://edge.invalid/functions/v1/ios-data/attachment', { method: 'POST', headers: { authorization: 'Bearer test-user-token', 'content-type': 'application/pdf', 'x-transaction-id': target }, body: new TextEncoder().encode('%PDF-1.4 synthetic') }));
    assert(response.status === (owned ? 201 : 404));
    const metadata = calls.find(call => call.url.endsWith('/rest/v1/attachments') && call.init?.method === 'POST');
    if (owned) {
      const values = JSON.parse(String(metadata?.init?.body));
      assert(values.transaction_id === target && !values.review_item_id && !values.split_bill_id);
      assert(!calls.some(call => call.url.includes('/rpc/')));
    } else assert(!metadata && !calls.some(call => call.url.includes('/storage/')));
  }, url => url.includes('/transactions?') ? Response.json(owned ? [{ id: target }] : []) : url.endsWith('/auth/v1/user') ? Response.json({ id: 'cb000000-0000-4000-8000-000000000001' }) : Response.json({}));
});
function request(body: unknown, path = 'ios-data', authorized = true) { return new Request(`https://edge.invalid/functions/v1/${path}`, { method: 'POST', headers: { 'content-type': 'application/json', ...(authorized ? { authorization: 'Bearer test-user-token' } : {}) }, body: JSON.stringify(body) }); }
for (const month of ['2026-10', '2026-10-01']) Deno.test(`budget normalizes native/web month (${month})`, async () => {
  await mocked(async calls => {
    const response = await data(request({ operation: 'upsert_budget', payload: { category_id: 'synthetic-category', month, limit_amount: '4000' } }));
    assert(response.status === 200); assert(calls.length === 1);
    const values = JSON.parse(String(calls[0].init?.body));
    assert(values.month === '2026-10-01'); assert(values.limit_amount === '4000');
  }, () => new Response(null, { status: 204 }));
});
Deno.test('budget rejects invalid month without database writes', async () => {
  await mocked(async calls => {
    for (const month of ['2026-00', '2026-13', '2026-10-02', '', '2026-10-01T00:00:00Z']) {
      const response = await data(request({ operation: 'upsert_budget', payload: { month, category_id: 'synthetic-category', limit_amount: '4000' } }));
      assert(response.status === 422);
    }
    assert(calls.length === 0);
  }, () => { throw new Error('Invalid month reached database'); });
});
async function mocked(run: (calls: { url: string; init?: RequestInit }[]) => Promise<void>, responder: (url: string, init?: RequestInit) => Response | Promise<Response>) {
  const originalFetch = globalThis.fetch, calls: { url: string; init?: RequestInit }[] = [];
  globalThis.fetch = (input, init) => { const url = String(input); calls.push({ url, init }); return Promise.resolve(responder(url, init)); };
  try { await run(calls); } finally { globalThis.fetch = originalFetch; }
}
Deno.test('web/iOS ledger gateway: same operation, decimal payload, user JWT; restore transfer route', async () => {
  await mocked(async calls => {
    const payload = { p_client_mutation_id: 'a1000000-0000-4000-8000-000000000001', p_transfer_id: 'a2000000-0000-4000-8000-000000000001', p_expected_version: 2 };
    const response = await ledger(request({ operation: 'restore_transfer', payload }, 'ledger'));
    assert(response.status === 200); assert(calls[0].url.endsWith('/rpc/api_restore_transfer'));
    assert(JSON.stringify(JSON.parse(String(calls[0].init?.body))) === JSON.stringify(payload));
    assert((calls[0].init?.headers as Record<string,string>).authorization === 'Bearer test-user-token');
    assert(!(String(calls[0].init?.body)).includes('test-server-only-key'));
  }, () => Response.json({ schema_version: '1.0.0', data: { id: 'transfer', version: 3 } }));
});
Deno.test('gateway auth and CORS failures never call upstream', async () => {
  await mocked(async calls => { const response = await ledger(request({}, 'ledger', false)); assert(response.status === 401); assert((await response.json()).code === 'UNAUTHORIZED'); assert(calls.length === 0); const options = await ledger(new Request('https://edge.invalid', { method:'OPTIONS' })); assert(options.status === 204); assert(options.headers.get('access-control-allow-origin') === 'http://127.0.0.1:5173'); }, () => { throw new Error('unexpected upstream request'); });
});
Deno.test('import creates only pending review with fingerprint; no ledger posting', async () => {
  await mocked(async calls => { const response = await data(request({operation:'add_review_item',payload:{id:'review',source:'pasted_text',fingerprint:'sha256-synthetic',amount:{value:'75000'},merchant:{value:'TOKO'}}})); assert(response.ok); const body=JSON.parse(String(calls[0].init?.body)); assert(body.status==='pending'); assert(body.extracted_fields.fingerprint==='sha256-synthetic'); assert(calls.every(call=>!call.url.includes('/rpc/'))); },()=>new Response('',{status:201}));
});
Deno.test('malformed attachment MIME rejected before storage upload', async()=>{
  await mocked(async calls=>{const response=await data(new Request('https://edge.invalid/functions/v1/ios-data/attachment',{method:'POST',headers:{authorization:'Bearer test-user-token','content-type':'application/pdf','x-review-item-id':'a1000000-0000-4000-8000-000000000001'},body:new Uint8Array([137,80,78,71,13,10,26,10])}));assert(response.status===422);assert(calls.length===0);},()=>{throw new Error('unexpected upload');});
});
Deno.test('account deletion fails closed when storage inventory fails; identity not deleted',async()=>{
  await mocked(async calls=>{const response=await data(request({operation:'request_account_deletion',payload:{password:'synthetic-password'}}));assert(response.status>=400);assert(!calls.some(call=>call.init?.method==='DELETE'&&call.url.includes('/admin/users/')));},(url)=>url.endsWith('/auth/v1/user')?Response.json({id:'synthetic-user',email:'synthetic@example.invalid'}):url.includes('/token?')?Response.json({access_token:'reauthenticated',user:{id:'synthetic-user'}}):new Response('storage unavailable',{status:500}));
});
Deno.test('account deletion verifies every removal and identity disappearance',async()=>{
  let listings=0;
  await mocked(async calls=>{const response=await data(request({operation:'request_account_deletion',payload:{password:'synthetic-password'}}));assert(response.ok);const removal=calls.find(call=>call.url.endsWith('/object/attachments')&&call.init?.method==='DELETE');assert(removal);assert(JSON.parse(String(removal.init?.body)).prefixes[0]==='synthetic-user/bill.png');assert(calls.at(-1)?.init?.method!== 'DELETE');},(url,init)=>{
    if(url.endsWith('/auth/v1/user'))return Response.json({id:'synthetic-user',email:'synthetic@example.invalid'});
    if(url.includes('/token?'))return Response.json({access_token:'reauthenticated',user:{id:'synthetic-user'}});
    if(url.endsWith('/object/list/attachments'))return Response.json(++listings===1?[{id:'object',name:'bill.png'}]:[]);
    if(url.includes('/admin/users/')&&init?.method!=='DELETE')return new Response('',{status:404});
    return Response.json({});
  });
});
Deno.test('OAuth account deletion verifies recent owner without requesting an application password',async()=>{
  const claims={sub:'synthetic-user',amr:[{method:'oauth',timestamp:Math.floor(Date.now()/1000)}]};
  const token=`synthetic.${btoa(JSON.stringify(claims)).replace(/=/g,'')}.test`;
  await mocked(async calls=>{
    const value=request({operation:'request_account_deletion',payload:{expected_user_id:'synthetic-user'}});
    value.headers.set('authorization',`Bearer ${token}`);
    const response=await data(value);
    assert(response.ok);
    assert(calls.some(call=>call.url.includes('/admin/users/')&&call.init?.method==='DELETE'));
    assert(!calls.some(call=>call.url.includes('/token?')));
  },(url,init)=>{
    if(url.endsWith('/auth/v1/user'))return Response.json({id:'synthetic-user'});
    if(url.endsWith('/object/list/attachments'))return Response.json([]);
    if(url.includes('/admin/users/')&&init?.method!=='DELETE')return new Response('',{status:404});
    return Response.json({});
  });
});
Deno.test('OAuth deletion rejects stale, future, missing and foreign-owner authentication before storage',async()=>{
  const now=Math.floor(Date.now()/1000);
  for(const claims of [{sub:'other',amr:[{method:'oauth',timestamp:now}]},{sub:'synthetic-user',amr:[{method:'oauth',timestamp:now-301}]},{sub:'synthetic-user',amr:[{method:'oauth',timestamp:now+60}]},{sub:'synthetic-user'}]) {
    await mocked(async calls=>{
      const value=request({operation:'request_account_deletion',payload:{expected_user_id:'synthetic-user'}});
      value.headers.set('authorization',`Bearer synthetic.${btoa(JSON.stringify(claims)).replace(/=/g,'')}.test`);
      const response=await data(value);assert(response.status===401);assert(calls.length===1);
    },()=>Response.json({id:'synthetic-user'}));
  }
});
Deno.test('full export ZIP supports 300KB attachment and signed decimal CSV; no partial success',async()=>{
  const dashboard={accounts:[{id:'cash',name:'Tunai'}],categories:[{id:'food',name:'Makan'}],transactions:[{id:'transaction',kind:'expense',amount:'75000',accountID:'cash',categoryID:'food',occurredAt:'2026-09-30T05:00:00Z',note:'=HYPERLINK(1)',merchant:'TOKO'}],splitBills:[],transfers:[]};
  await mocked(async()=>{const response=await exportData(request({}));assert(response.ok);assert(response.headers.get('content-type')==='application/zip');const bytes=new Uint8Array(await response.arrayBuffer());assert(bytes.length>300000);const text=new TextDecoder().decode(bytes);assert(text.includes('"-75000"'));assert(!text.includes('"\'-75000"'));assert(text.includes("'=HYPERLINK"));assert(text.includes('manifest.json'));assert(text.includes('aiConsent'));assert(text.includes('supportTickets'));},url=>url.includes('/dashboard-full')?Response.json(dashboard):/\/rest\/v1\/(ai_consents|support_tickets)/.test(url)?Response.json([]):url.includes('/rest/v1/attachments')?Response.json([{id:'attachment',storage_key:'user/bill.pdf',mime:'application/pdf',size_bytes:300000}]):new Response(new Uint8Array(300000),{status:200}));
  await mocked(async()=>{const response=await exportData(request({}));assert(!response.ok);},url=>url.includes('/dashboard-full')?Response.json(dashboard):/\/rest\/v1\/(ai_consents|support_tickets)/.test(url)?Response.json([]):url.includes('/rest/v1/attachments')?Response.json([{id:'attachment',storage_key:'user/bill.pdf',mime:'application/pdf',size_bytes:300000}]):new Response('',{status:500}));
});
