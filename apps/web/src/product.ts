import content from '../../../contracts/product-content.json';
import { cloudConfiguration } from './remote.ts';

export const productContent = content;
export const publicPages = ['about', 'privacy', 'terms', 'contact', 'faq', 'delete-account'];
export const productLinks = productContent.links;
export interface AIConsent { granted: boolean; policyVersion: string | null; updatedAt: string | null }
export interface SupportTicket { id: string; topic: string; description: string; status: string; reply?: string; createdAt: string }
export interface ProductInfo { policyVersion: string; supportEmail: string | null; authentication: string; scanConfigured: boolean; checkedAt: string }
export interface PlanningEntry { id: string; sourceID: string; kind: string; amount: string; occurredAt: string; merchant?: string; note?: string }
export interface PlanningHistory { items: PlanningEntry[]; nextCursor: { occurredAt: string; id: string } | null }
export async function fetchProductInfo(signal?: AbortSignal): Promise<ProductInfo> {
  if (!cloudConfiguration) throw new Error('Layanan belum dikonfigurasi.');
  const response = await fetch(`${cloudConfiguration.url}/functions/v1/product-info`, { headers: { apikey: cloudConfiguration.key }, signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(10000)]) : AbortSignal.timeout(10000) });
  if (!response.ok) throw new Error('Status layanan belum dapat diperiksa.');
  const value = await response.json();
  if (typeof value.checkedAt !== 'string' || typeof value.authentication !== 'string' || typeof value.scanConfigured !== 'boolean') throw new Error('Status layanan tidak valid.');
  return { ...value, supportEmail: typeof value.supportEmail === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.supportEmail) ? value.supportEmail : null };
}
