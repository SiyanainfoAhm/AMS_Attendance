import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getClientIpForPostgres, jsonResponse, optionsResponse } from "../_shared/http.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse();
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, { status: 405 });

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, { status: 400 });
  }

  const { email, password, clientType, deviceId } = (body ?? {}) as Record<string, unknown>;
  if (typeof email !== "string" || typeof password !== "string") {
    return jsonResponse({ error: "email_and_password_required" }, { status: 400 });
  }

  const svc = tryGetServiceClient();
  if (!svc.ok) return jsonResponse({ error: "server_misconfigured", details: svc.error }, { status: 500 });

  const { data, error } = await svc.client.rpc("ams_sp_user_login", {
    p_email: email,
    p_password: password,
    p_client_type: typeof clientType === "string" ? clientType : "web",
    p_device_id: typeof deviceId === "string" ? deviceId : null,
    p_ip_address: getClientIpForPostgres(req),
    p_user_agent: req.headers.get("user-agent") ?? null
  });

  if (error) {
    return jsonResponse(
      { error: "login_failed", details: error.message },
      { status: 401 }
    );
  }

  return jsonResponse({ ok: true, result: data });
});

