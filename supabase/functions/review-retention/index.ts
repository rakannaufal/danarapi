type ClaimedReview = { id: string; storage_keys: string[] };

export async function cleanupReviews(baseURL: string, serviceKey: string, transport: typeof fetch = fetch) {
  const headers = { authorization: `Bearer ${serviceKey}`, apikey: serviceKey, 'content-type': 'application/json' };
  const rpc = async (name: string, body: unknown) => {
    const response = await transport(`${baseURL}/rest/v1/rpc/${name}`, { method: 'POST', headers, body: JSON.stringify(body) });
    if (!response.ok) throw new Error('Retention database operation failed');
    return response.status === 204 ? null : response.json();
  };
  const reviews = await rpc('claim_expired_reviews', { p_limit: 50 }) as ClaimedReview[];
  let deleted = 0, failed = 0;
  for (const review of reviews) {
    try {
      for (const key of review.storage_keys) {
        const objectURL = `${baseURL}/storage/v1/object/authenticated/attachments/${key.split('/').map(encodeURIComponent).join('/')}`;
        const removed = await transport(`${baseURL}/storage/v1/object/attachments`, { method: 'DELETE', headers, body: JSON.stringify({ prefixes: [key] }) });
        if (!removed.ok && removed.status !== 404) throw new Error('Storage removal failed');
        const remaining = await transport(objectURL, { method: 'GET', headers });
        const missing = remaining.status === 404 || (remaining.status === 400 && String((await remaining.json().catch(() => ({}))).statusCode) === '404');
        if (!missing) throw new Error('Storage removal not verified');
      }
      await rpc('finish_expired_review', { p_review_id: review.id });
      deleted++;
    } catch { failed++; }
  }
  return { processed: reviews.length, deleted, failed };
}

export const retentionHandler = async (request: Request) => {
  const secret = Deno.env.get('RETENTION_JOB_SECRET');
  if (!secret || secret.length < 32 || secret.startsWith('replace-') || request.headers.get('authorization') !== `Bearer ${secret}`) return new Response('Unauthorized', { status: 401 });
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  try {
    const result = await cleanupReviews(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    return Response.json(result, { status: result.failed ? 503 : 200 });
  } catch { return Response.json({ error: 'Retention cleanup failed; retry required' }, { status: 503 }); }
};
Deno.serve(retentionHandler);
