export function corsFor(request: Request, extraHeaders = ''): Record<string, string> {
  const configured = Deno.env.get('ALLOWED_ORIGINS') || Deno.env.get('ALLOWED_ORIGIN') || 'http://127.0.0.1:5173,http://localhost:5173';
  const origins = configured.split(',').map(origin => origin.trim()).filter(Boolean);
  const origin = request.headers.get('origin');
  const allowed = origin ? origins.includes(origin) ? origin : undefined : origins[0];
  return {
    ...(allowed ? { 'access-control-allow-origin': allowed } : {}),
    'access-control-allow-headers': ['authorization', 'apikey', 'content-type', 'x-client-info', extraHeaders].filter(Boolean).join(', '),
    'access-control-allow-methods': 'POST, OPTIONS',
    vary: 'Origin',
  };
}
