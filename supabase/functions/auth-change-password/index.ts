import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, jsonResponse, optionsResponse } from "../_shared/http.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse();
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, { status: 405 });

  const accessToken = getAmsAccessToken(req);
  if (!accessToken) return jsonResponse({ error: "missing_access_token" }, { status: 401 });

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, { status: 400 });
  }

  const b = (body ?? {}) as Record<string, unknown>;
  const oldPassword = typeof b.oldPassword === "string" ? b.oldPassword : null;
  const newPassword = typeof b.newPassword === "string" ? b.newPassword : null;

  if (!oldPassword || !newPassword) {
    return jsonResponse({ error: "old_password_and_new_password_required" }, { status: 400 });
  }
  if (newPassword.length < 8) {
    return jsonResponse({ error: "password_too_short", details: "Password must be at least 8 characters." }, { status: 400 });
  }
  if (oldPassword === newPassword) {
    return jsonResponse({ error: "new_password_must_differ" }, { status: 400 });
  }

  const svc = tryGetServiceClient();
  if (!svc.ok) return jsonResponse({ error: "server_misconfigured", details: svc.error }, { status: 500 });

  const { data, error } = await svc.client.rpc("ams_sp_change_password", {
    p_access_token: accessToken,
    p_old_password: oldPassword,
    p_new_password: newPassword
  });

  if (error) {
    const msg = error.message ?? "";
    const lower = msg.toLowerCase();
    if (lower.includes("invalid_session")) {
      return jsonResponse({ error: "invalid_session", details: msg }, { status: 401 });
    }
    if (lower.includes("invalid_old_password")) {
      return jsonResponse({ error: "invalid_old_password", details: msg }, { status: 401 });
    }
    if (lower.includes("password_too_short")) {
      return jsonResponse({ error: "password_too_short", details: msg }, { status: 400 });
    }
    if (lower.includes("user_not_found")) {
      return jsonResponse({ error: "user_not_found", details: msg }, { status: 400 });
    }
    return jsonResponse({ error: "change_password_failed", details: msg }, { status: 400 });
  }

  return jsonResponse({ ok: true, result: data });
});
