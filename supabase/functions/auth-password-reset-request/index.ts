import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getClientIpForPostgres, jsonResponse, optionsResponse } from "../_shared/http.ts";

function envFlagTrue(name: string): boolean {
  return (Deno.env.get(name) ?? "").toLowerCase() === "true";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse();
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, { status: 405 });

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, { status: 400 });
  }

  const email = (body as Record<string, unknown>)?.email;
  if (typeof email !== "string") {
    return jsonResponse({ error: "email_required" }, { status: 400 });
  }

  const returnTokenToClient = envFlagTrue("AMS_RETURN_RESET_TOKEN_IN_RESPONSE");

  const svc = tryGetServiceClient();
  if (!svc.ok) return jsonResponse({ error: "server_misconfigured", details: svc.error }, { status: 500 });

  const { data, error } = await svc.client.rpc("ams_sp_request_password_reset", {
    p_email: email,
    p_ip_address: getClientIpForPostgres(req),
    p_user_agent: req.headers.get("user-agent") ?? null,
    p_include_token_in_response: returnTokenToClient
  });

  if (error) {
    return jsonResponse({ error: "request_failed", details: error.message }, { status: 400 });
  }

  const resetToken = (data as Record<string, unknown> | null)?.reset_token;
  const token = typeof resetToken === "string" ? resetToken : null;

  // Preserve non-enumeration response shape.
  // In dev, allow returning token for testing.
  const result: Record<string, unknown> = { requested: true };
  if (returnTokenToClient && token) result.reset_token = token;
  return jsonResponse({ ok: true, result });
});
