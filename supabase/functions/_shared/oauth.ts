export function hasRecentOAuth(claims: { sub?: string; amr?: { method: string; timestamp: number }[] }, userID: string, now = Date.now() / 1000): boolean {
  return claims.sub === userID && Array.isArray(claims.amr) && claims.amr.some(row => row.method === 'oauth' && Number.isFinite(row.timestamp) && row.timestamp <= now + 30 && now - row.timestamp <= 300);
}
