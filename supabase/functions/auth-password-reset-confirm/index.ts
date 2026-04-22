import { tryGetServiceClient } from "../_shared/supabase.ts";
import { jsonResponse, optionsResponse } from "../_shared/http.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse();
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, { status: 405 });

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, { status: 400 });
  }

  const b = (body ?? {}) as Record<string, unknown>;
  const resetToken = typeof b.resetToken === "string" ? b.resetToken : null;
  const newPassword = typeof b.newPassword === "string" ? b.newPassword : null;

  if (!resetToken || !newPassword) {
    return jsonResponse({ error: "reset_token_and_new_password_required" }, { status: 400 });
  }

  const svc = tryGetServiceClient();
  if (!svc.ok) return jsonResponse({ error: "server_misconfigured", details: svc.error }, { status: 500 });

  const { data, error } = await svc.client.rpc("ams_sp_reset_password", {
    p_reset_token: resetToken,
    p_new_password: newPassword
  });

  if (error) {
    const msg = error.message ?? "";
    const lower = msg.toLowerCase();
    if (lower.includes("invalid_or_expired_reset_token")) {
      return jsonResponse({ error: "invalid_or_expired_reset_token", details: msg }, { status: 401 });
    }
    if (lower.includes("password_too_short")) {
      return jsonResponse({ error: "password_too_short", details: msg }, { status: 400 });
    }
    return jsonResponse({ error: "reset_failed", details: msg }, { status: 400 });
  }

  return jsonResponse({ ok: true, result: data });
});
