import { corsHeaders } from "./cors.ts";

export function jsonResponse(
  body: unknown,
  init: ResponseInit & { status?: number } = {}
) {
  const headers = new Headers(init.headers);
  headers.set("content-type", "application/json; charset=utf-8");
  Object.entries(corsHeaders).forEach(([k, v]) => headers.set(k, v));
  return new Response(JSON.stringify(body), { ...init, headers });
}

export function mergeResponseHeaders(base: HeadersInit | undefined, extra: HeadersInit): Headers {
  const h = new Headers(base);
  new Headers(extra).forEach((v, k) => h.set(k, v));
  return h;
}

export function optionsResponse() {
  return new Response(null, { status: 204, headers: corsHeaders });
}

export function getBearerToken(req: Request): string | null {
  const h = req.headers.get("authorization");
  if (!h) return null;
  const m = /^Bearer\s+(.+)$/i.exec(h);
  return m?.[1] ?? null;
}

export function getAmsAccessToken(req: Request): string | null {
  const h = req.headers.get("x-ams-access-token");
  if (h && h.trim().length > 0) return h.trim();
  return null;
}

function isLikelyIpLiteral(v: string): boolean {
  // Keep it simple: accept IPv4 or IPv6 literal-ish strings; Postgres will validate inet.
  // Reject obvious non-IP values (empty, includes spaces beyond trimming, etc.).
  if (!v) return false;
  if (v.includes(" ")) return false;
  return /^[0-9.]+$/.test(v) || /^[0-9a-fA-F:]+$/.test(v);
}

export function getClientIpForPostgres(req: Request): string | null {
  // Common format: "client, proxy1, proxy2"
  const xff = req.headers.get("x-forwarded-for");
  if (xff) {
    const first = xff
      .split(",")
      .map((s) => s.trim())
      .find((s) => isLikelyIpLiteral(s));
    if (first) return first;
  }

  const xri = req.headers.get("x-real-ip");
  if (xri && isLikelyIpLiteral(xri.trim())) return xri.trim();

  return null;
}

