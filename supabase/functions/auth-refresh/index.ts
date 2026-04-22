import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getClientIpForPostgres, jsonResponse, optionsResponse } from "../_shared/http.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse();
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, { status: 405 });

  const refreshToken =
    req.headers.get("x-ams-refresh-token") ??
    (() => {
      // also allow JSON body for convenience
      return null;
    })();

  let bodyToken: string | null = null;
  if (!refreshToken) {
    try {
      const body = (await req.json()) as Record<string, unknown>;
      bodyToken = typeof body?.refreshToken === "string" ? body.refreshToken : null;
    } catch {
      // ignore
    }
  }

  const token = refreshToken ?? bodyToken;
  if (!token) return jsonResponse({ error: "refresh_token_required" }, { status: 400 });

  const svc = tryGetServiceClient();
  if (!svc.ok) return jsonResponse({ error: "server_misconfigured", details: svc.error }, { status: 500 });

  const { data, error } = await svc.client.rpc("ams_sp_refresh_session", {
    p_refresh_token: token,
    p_client_type: "web",
    p_device_id: null,
    p_ip_address: getClientIpForPostgres(req),
    p_user_agent: req.headers.get("user-agent") ?? null
  });

  if (error) {
    return jsonResponse({ error: "refresh_failed", details: error.message }, { status: 401 });
  }

  return jsonResponse({ ok: true, result: data });
});

