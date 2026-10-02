export const policyVersion = '2026-10-02';
export function consentAllowsScan(value: unknown): boolean {
  if (!value || typeof value !== 'object') return false;
  const consent = value as Record<string, unknown>;
  return consent.granted === true && consent.policy_version === policyVersion;
}
