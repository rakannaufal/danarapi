import { corsFor } from '../_shared/cors.ts';
import { policyVersion } from '../_shared/product.ts';

Deno.serve(async request => {
  const headers = { ...corsFor(request), 'access-control-allow-methods': 'GET, OPTIONS', 'cache-control': 'no-store' };
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (request.method !== 'GET') return Response.json({ message: 'Gunakan GET.' }, { status: 405, headers });
  const email = Deno.env.get('SUPPORT_EMAIL')?.trim();
  const base = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_ANON_KEY');
  let authentication = 'unavailable';
  if (base && key) {
    try {
      const response = await fetch(`${base}/auth/v1/settings`, { headers: { apikey: key }, signal: AbortSignal.timeout(6000) });
      const value = response.ok ? await response.json() : null;
      authentication = value?.external?.google === true ? 'available' : 'unavailable';
    } catch { authentication = 'unavailable'; }
  }
  return Response.json({
    policyVersion,
    supportEmail: email && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null,
    authentication,
    scanConfigured: !!Deno.env.get('GEMINI_API_KEY'),
    checkedAt: new Date().toISOString(),
  }, { headers });
});
