import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { assertDecimalPayload, type Snapshot, type Report } from './domain.ts';
import { resolveCloudConfiguration } from './cloud.ts';

export const cloudConfiguration = resolveCloudConfiguration(import.meta.env);

export function authClient(): SupabaseClient | null {
  if (!cloudConfiguration) return null;
  const { url, key } = cloudConfiguration;
  return createClient(url, key, { auth: { storage: sessionStorage, storageKey: 'danarapi.auth', persistSession: true, autoRefreshToken: true, detectSessionInUrl: false, flowType: 'pkce' } });
}
export const dataOperations = new Set(['update_account', 'archive_account', 'update_category', 'archive_category', 'add_review_item', 'update_review_item', 'reject_review_item', 'restore_review_item', 'merge_review_item', 'clear_review_duplicate', 'confirm_review_item', 'upsert_budget', 'request_account_deletion', 'save_merchant_rule', 'delete_merchant_rule']);
export class RemoteRepository {
  private mutations = new Map<string, string>();
  constructor(readonly client: SupabaseClient) {}
  async request(path: string, body?: unknown, headers?: Record<string, string>, binary = false, signal?: AbortSignal): Promise<any> {
    if (!navigator.onLine) throw new Error('Perlu internet. Perubahan belum disimpan.');
    const { data: { session } } = await this.client.auth.getSession();
    if (!session) throw new Error('Sesi kedaluwarsa. Masuk kembali.');
    if (!cloudConfiguration) throw new Error('Backend belum dikonfigurasi.');
    const response = await fetch(`${cloudConfiguration.url}/functions/v1/${path}`, {
      method: 'POST', headers: { apikey: cloudConfiguration.key, authorization: `Bearer ${session.access_token}`, 'content-type': 'application/json', ...headers },
      body: body instanceof Blob ? body : JSON.stringify(body ?? {}), signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(110000)]) : AbortSignal.timeout(45000),
    });
    if (!response.ok) { const error = await response.json().catch(() => ({})); if (response.status === 404 && error.code === 'NOT_FOUND') throw new Error('Layanan cloud belum tersedia. Hubungi pengelola aplikasi.'); throw new Error(`${error.message ?? 'Permintaan gagal.'}${error.code ? ` (${error.code})` : ''}${error.request_id ? ` · ${error.request_id}` : ''}`); }
    return binary ? response.blob() : response.json();
  }
  async snapshot(): Promise<Snapshot> {
    const data = await this.request('ios-data/dashboard');
    let cursor = data.nextTransactionCursor;
    const seen = new Set<string>(data.transactions.map((row: { id: string }) => row.id));
    while (cursor) {
      const page = await this.request('ios-data/transactions', { cursor });
      for (const row of page.items) if (!seen.has(row.id)) { data.transactions.push(row); seen.add(row.id); }
      if (page.nextCursor && JSON.stringify(page.nextCursor) === JSON.stringify(cursor)) throw new Error('Cursor backend tidak bergerak. Coba lagi.');
      cursor = page.nextCursor;
    }
    assertDecimalPayload(data);
    return data;
  }
  async report(from: string, to: string): Promise<Report> { return this.request('ios-data/report', { startDate: from, endDate: to }); }
  async mutate(operation: string, payload: Record<string, unknown>) {
    if (dataOperations.has(operation)) return this.request('ios-data', { operation, payload });
    const canonical = JSON.stringify({ operation, payload: { ...payload, p_client_mutation_id: undefined } });
    const mutation = this.mutations.get(canonical) ?? String(payload.p_client_mutation_id ?? crypto.randomUUID());
    this.mutations.set(canonical, mutation);
    const result = await this.request('ledger', { operation, payload: { ...payload, p_client_mutation_id: mutation } });
    this.mutations.delete(canonical);
    return result;
  }
  async upload(reviewID: string, file: File) { return this.request('ios-data/attachment', file, { 'content-type': file.type, 'x-review-item-id': reviewID, 'x-file-name': encodeURIComponent(file.name) }); }
  async uploadPosted(kind: 'transaction' | 'bill', targetID: string, file: File) { return this.request('ios-data/attachment', file, { 'content-type': file.type, [kind === 'transaction' ? 'x-transaction-id' : 'x-split-bill-id']: targetID, 'x-file-name': encodeURIComponent(file.name) }); }
  async export() { return this.request('export-data', undefined, undefined, true) as Promise<Blob>; }
}
