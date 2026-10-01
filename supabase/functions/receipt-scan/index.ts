import { readBounded, scanReceipt, validateImages, type ScanStore } from '../_shared/receipt-scan.ts';
import { scanMessages } from '../_shared/receipt.ts';
import { corsFor } from '../_shared/cors.ts';

function configInteger(name: string, fallback: number, minimum: number, maximum: number) { const value = Number(Deno.env.get(name) ?? fallback); if (!Number.isInteger(value) || value < minimum || value > maximum) throw new Error('config_error'); return value; }
Deno.serve(async request => {
  const cors = corsFor(request);
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (request.method !== 'POST') return Response.json({ message: 'Gunakan POST.' }, { status: 405, headers: cors });
  const authorization = request.headers.get('authorization');
  if (!authorization?.startsWith('Bearer ')) return Response.json({ message: 'Sesi diperlukan.' }, { status: 401, headers: cors });
  try {
    const base = Deno.env.get('SUPABASE_URL'); const key = Deno.env.get('SUPABASE_ANON_KEY'); const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!base || !key || !serviceKey) throw new Error('config_error');
    const auth = await fetch(`${base}/auth/v1/user`, { headers: { authorization, apikey: key }, signal: AbortSignal.timeout(10000) });
    if (!auth.ok) return Response.json({ message: 'Sesi kedaluwarsa.' }, { status: 401, headers: cors });
    const user = await auth.json(); if (!user.id) return Response.json({ message: 'Sesi tidak valid.' }, { status: 401, headers: cors });
    if (!request.headers.get('content-type')?.startsWith('application/json')) throw new Error('invalid_image');
    const body = JSON.parse(new TextDecoder().decode(await readBounded(request, 5700000)));
    const { images, hash } = await validateImages(body.images);
    const daily = configInteger('SCAN_DAILY_LIMIT', 50, 1, 10000); const interval = configInteger('SCAN_INTERVAL_MS', 4000, 0, 60000);
    async function rpc(name: string, payload: unknown) {
      const response = await fetch(`${base}/rest/v1/rpc/${name}`, { method: 'POST', headers: { authorization: `Bearer ${serviceKey}`, apikey: serviceKey!, 'content-type': 'application/json' }, body: JSON.stringify(payload), signal: AbortSignal.timeout(15000) });
      if (!response.ok) throw new Error('service_error'); return response.json();
    }
    const store: ScanStore = {
      claim: (userID, hash) => rpc('claim_receipt_scan', { p_user_id: userID, p_hash: hash, p_daily_limit: daily }),
      reserve: (userID, hash) => rpc('reserve_receipt_scan_call', { p_user_id: userID, p_hash: hash, p_interval_ms: interval }),
      finish: async (userID, hash, result) => { await rpc('finish_receipt_scan', { p_user_id: userID, p_hash: hash, p_result: result }); },
    };
    const result = await scanReceipt({ userID: user.id, hash, images, apiKey: Deno.env.get('GEMINI_API_KEY') ?? '', model: Deno.env.get('GEMINI_MODEL') ?? 'gemini-3.5-flash-lite', fallbackModel: Deno.env.get('GEMINI_FALLBACK_MODEL'), store });
    return Response.json({ ...result, message: scanMessages[result.status] }, { headers: cors });
  } catch (error) {
    const status = error instanceof SyntaxError || (error instanceof Error && ['invalid_image', 'size_limit', 'empty_body'].includes(error.message)) ? 'invalid_image' : error instanceof Error && error.message === 'config_error' ? 'config_error' : 'service_error';
    return Response.json({ status, message: scanMessages[status] }, { status: status === 'invalid_image' ? 400 : 200, headers: cors });
  }
});
