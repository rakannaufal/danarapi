export const cloudProject = {
  url: 'https://zoccosfjulasqxczhvfm.supabase.co',
  key: 'sb_publishable_HFNe0r92MxPPmck_SxfvdA_dwVecyjx',
};

export function resolveCloudConfiguration(env: Record<string, string | undefined>) {
  const overridden = env.VITE_SUPABASE_URL !== undefined || env.VITE_SUPABASE_PUBLISHABLE_KEY !== undefined || env.VITE_SUPABASE_ANON_KEY !== undefined;
  const url = (overridden ? env.VITE_SUPABASE_URL : cloudProject.url)?.trim();
  const key = (overridden ? env.VITE_SUPABASE_PUBLISHABLE_KEY ?? env.VITE_SUPABASE_ANON_KEY : cloudProject.key)?.trim();
  if (!url || !key || key.startsWith('replace-') || key.startsWith('sb_secret_')) return null;
  try {
    const parsed = new URL(url);
    if (parsed.username || parsed.password || parsed.search || parsed.hash || parsed.pathname !== '/') return null;
    if (parsed.protocol !== 'https:' && !(parsed.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(parsed.hostname))) return null;
    if (key.startsWith('eyJ') && JSON.parse(atob(key.split('.')[1]!.replaceAll('-', '+').replaceAll('_', '/'))).role !== 'anon') return null;
    return { url: parsed.origin, key };
  } catch { return null; }
}

export async function ensureOAuthProvider(configuration: { url: string; key: string }, provider: 'google', request: typeof fetch = fetch) {
  if (provider !== 'google') throw new Error('Provider login tidak valid.');
  const response = await request(`${configuration.url}/auth/v1/settings`, { headers: { apikey: configuration.key }, signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error('Layanan login belum tersedia. Coba lagi nanti.');
  const settings = await response.json();
  if (settings.external?.[provider] !== true) throw new Error('Login Google belum diaktifkan. Hubungi pengelola aplikasi.');
}
