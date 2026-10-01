import { randomBytes, timingSafeEqual } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { scanReceipt, validateImages, type ScanStore } from '../../../supabase/functions/_shared/receipt-scan.ts';
import { scanMessages, type ScanResult } from '../../../supabase/functions/_shared/receipt.ts';

export function localScanStore(options: { dailyLimit?: number; interval?: number; now?: () => number } = {}): ScanStore {
  const now = options.now ?? Date.now;
  const entries = new Map<string, { started: number; calls: number; result?: ScanResult }>();
  let day = '', count = 0, nextCall = 0;
  return {
    async claim(_userID, hash) {
      const time = now();
      for (const [key, entry] of entries) if (time - entry.started >= 86400000) entries.delete(key);
      const existing = entries.get(hash);
      if (existing) {
        if (!existing.result && time - existing.started > 300000) existing.result = { status: 'service_error' };
        return existing.result ? { state: 'cached', result: existing.result } : { state: 'busy' };
      }
      const today = new Date(time).toISOString().slice(0, 10);
      if (day !== today) { day = today; count = 0; }
      if (count >= (options.dailyLimit ?? 50) || entries.size >= 500) return { state: 'quota_exceeded' };
      count++; entries.set(hash, { started: time, calls: 0 });
      return { state: 'new' };
    },
    async reserve(_userID, hash) {
      const entry = entries.get(hash), time = now();
      if (!entry || entry.calls >= 2 || nextCall - time > 60000) throw new Error('call_limit');
      const wait = Math.max(0, nextCall - time);
      entry.calls++; nextCall = time + wait + (options.interval ?? 4000);
      return wait;
    },
    async finish(_userID, hash, result) { const entry = entries.get(hash); if (entry) entry.result = result; },
  };
}

export function localScanHandler(options: { enabled: boolean; apiKey: string; model: string; fallbackModel?: string; dailyLimit?: number; interval?: number; fetch?: typeof fetch }) {
  const token = randomBytes(32).toString('hex');
  const store = localScanStore(options);
  return async (request: IncomingMessage, response: ServerResponse) => {
    const reply = (status: number, data: unknown) => { response.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' }); response.end(JSON.stringify(data)); };
    const host = request.headers.host ?? '', address = request.socket.remoteAddress;
    if (!['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(address ?? '') || !/^(localhost|127\.0\.0\.1|\[::1\]):\d+$/.test(host) || (request.headers.origin && request.headers.origin !== `http://${host}`) || request.headers['sec-fetch-site'] === 'cross-site') { reply(403, { status: 'config_error' }); return; }
    const validSettings = Number.isInteger(options.dailyLimit ?? 50) && (options.dailyLimit ?? 50) >= 1 && (options.dailyLimit ?? 50) <= 10000 && Number.isInteger(options.interval ?? 4000) && (options.interval ?? 4000) >= 0 && (options.interval ?? 4000) <= 60000;
    const configured = options.enabled && !!options.apiKey && validSettings;
    if (request.method === 'GET') { reply(200, configured ? { configured, token } : { configured }); return; }
    if (request.method !== 'POST') { reply(405, { status: 'config_error' }); return; }
    if (request.headers.origin !== `http://${host}` || request.headers['x-danarapi-local-scan'] !== token) { reply(403, { status: 'config_error' }); return; }
    if (!configured) { reply(200, { status: 'config_error', message: scanMessages.config_error }); return; }
    if (!request.headers['content-type']?.startsWith('application/json') || Number(request.headers['content-length']) > 5700000) { reply(400, { status: 'invalid_image' }); return; }
    try {
      const chunks: Buffer[] = []; let size = 0;
      for await (const chunk of request) { size += chunk.length; if (size > 5700000) { reply(413, { status: 'invalid_image' }); return; } chunks.push(Buffer.from(chunk)); }
      const { images, hash } = await validateImages(JSON.parse(Buffer.concat(chunks).toString('utf8')).images);
      const result = await scanReceipt({ ...options, userID: 'local-development', images, hash, store });
      reply(200, { ...result, message: scanMessages[result.status] });
    } catch (error) {
      const status = error instanceof SyntaxError || (error instanceof Error && error.message === 'invalid_image') ? 'invalid_image' : 'service_error';
      reply(status === 'invalid_image' ? 400 : 200, { status, message: scanMessages[status] });
    }
  };
}

export function nativeScanHandler(options: { token: string; host: string; apiKey: string; model: string; fallbackModel?: string; dailyLimit?: number; interval?: number; fetch?: typeof fetch }) {
  if (!/^[a-f0-9]{64}$/.test(options.token) || !options.apiKey || !options.host || !Number.isInteger(options.dailyLimit ?? 50) || (options.dailyLimit ?? 50) < 1 || (options.dailyLimit ?? 50) > 10000 || !Number.isInteger(options.interval ?? 4000) || (options.interval ?? 4000) < 0 || (options.interval ?? 4000) > 60000) throw new Error('Invalid native scan configuration');
  const store = localScanStore(options);
  let active = 0;
  return async (request: IncomingMessage, response: ServerResponse) => {
    const reply = (status: number, data: unknown) => { response.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' }); response.end(JSON.stringify(data)); };
    const header = request.headers['x-danarapi-native-scan'];
    const credential = typeof header === 'string' ? Buffer.from(header) : Buffer.alloc(0);
    const expected = Buffer.from(options.token);
    if (!(request.socket as typeof request.socket & { encrypted?: boolean }).encrypted || request.headers.host !== options.host || request.headers.origin || request.headers['sec-fetch-site'] || credential.length !== expected.length || !timingSafeEqual(credential, expected)) { reply(403, { status: 'config_error' }); return; }
    if (request.url !== '/scan') { reply(404, { status: 'config_error' }); return; }
    if (request.method === 'GET') { reply(200, { configured: true }); return; }
    if (request.method !== 'POST') { reply(405, { status: 'config_error' }); return; }
    if (active >= 2) { reply(429, { status: 'busy' }); return; }
    if (!request.headers['content-type']?.startsWith('application/json') || Number(request.headers['content-length']) > 5700000) { reply(400, { status: 'invalid_image' }); return; }
    active++;
    try {
      const chunks: Buffer[] = []; let size = 0;
      for await (const chunk of request) { size += chunk.length; if (size > 5700000) { reply(413, { status: 'invalid_image' }); return; } chunks.push(Buffer.from(chunk)); }
      const { images, hash } = await validateImages(JSON.parse(Buffer.concat(chunks).toString('utf8')).images);
      const result = await scanReceipt({ ...options, userID: 'native-development', images, hash, store });
      reply(200, { ...result, message: scanMessages[result.status] });
    } catch (error) {
      const status = error instanceof SyntaxError || (error instanceof Error && error.message === 'invalid_image') ? 'invalid_image' : 'service_error';
      reply(status === 'invalid_image' ? 400 : 200, { status, message: scanMessages[status] });
    } finally { active--; }
  };
}
