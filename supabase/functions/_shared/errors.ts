export interface PublicError {
  code: string;
  message: string;
  request_id: string;
  details: Record<string, unknown>;
}

const STATUS_BY_CODE: Record<string, number> = {
  VALIDATION: 422,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT_VERSION: 409,
  DUPLICATE_MUTATION: 409,
  OBLIGATION_EXCEEDED: 409,
  STRUCTURE_LOCKED: 409,
  QUOTA_EXCEEDED: 429,
  REQUIRES_ONLINE: 503,
  INTERNAL: 500
};

export function normalizeError(raw: unknown, requestId: string): { status: number; body: PublicError } {
  let parsed: Record<string, unknown> = {};
  if (raw && typeof raw === "object") {
    const candidate = raw as Record<string, unknown>;
    if (typeof candidate.message === "string") {
      try {
        parsed = JSON.parse(candidate.message);
      } catch {
        parsed = candidate;
      }
    }
  }
  const code = typeof parsed.code === "string" && parsed.code in STATUS_BY_CODE ? parsed.code : "INTERNAL";
  return {
    status: STATUS_BY_CODE[code],
    body: {
      code,
      message: typeof parsed.message === "string" ? parsed.message : "Permintaan tidak dapat diproses.",
      request_id: requestId,
      details: parsed.details && typeof parsed.details === "object" ? parsed.details as Record<string, unknown> : {}
    }
  };
}

