import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, jsonResponse, optionsResponse } from "../_shared/http.ts";

const PLATFORMS = ["android", "ios", "web"] as const;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse();

  const accessToken = getAmsAccessToken(req);
  if (!accessToken) return jsonResponse({ error: "missing_access_token" }, { status: 401 });

  const svc = tryGetServiceClient();
  if (!svc.ok) return jsonResponse({ error: "server_misconfigured", details: svc.error }, { status: 500 });

  const { data: sess } = await svc.client.rpc("ams_fn_validate_user_session", { p_access_token: accessToken });
  if (!Array.isArray(sess) || sess.length === 0) return jsonResponse({ error: "invalid_session" }, { status: 401 });
  const session = sess[0] as { user_id: string; company_id: string | null };
  if (!session.company_id) return jsonResponse({ error: "company_not_selected" }, { status: 403 });

  const url = new URL(req.url);
  const action = (url.searchParams.get("action") ?? "").trim();

  if (req.method === "POST" && action === "disable-all") {
    const now = new Date().toISOString();
    const { error } = await svc.client
      .from("ams_push_token")
      .update({ is_enabled: false, last_seen_at: now, updated_at: now })
      .eq("ams_user_id", session.user_id);

    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });
    return jsonResponse({ ok: true, result: { disabledAll: true } });
  }

  if (req.method === "POST" && action === "disable") {
    const body = await req.json().catch(() => null);
    const token = String(body?.token ?? "").trim();
    if (!token) return jsonResponse({ error: "invalid_body", details: "token_required" }, { status: 400 });

    const { error } = await svc.client
      .from("ams_push_token")
      .update({ is_enabled: false, last_seen_at: new Date().toISOString() })
      .eq("ams_user_id", session.user_id)
      .eq("push_token", token);

    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });
    return jsonResponse({ ok: true, result: { disabled: true } });
  }

  if (req.method === "POST") {
    const body = await req.json().catch(() => null);
    const token = String(body?.token ?? "").trim();
    if (!token) return jsonResponse({ error: "invalid_body", details: "token_required" }, { status: 400 });

    const platformRaw = String(body?.platform ?? "").trim().toLowerCase();
    const platform = (PLATFORMS as readonly string[]).includes(platformRaw) ? platformRaw : null;
    const deviceId = body?.deviceId == null ? null : String(body.deviceId).trim();

    // Upsert-like behavior on (user_id, push_token).
    const now = new Date().toISOString();
    const { data: existing } = await svc.client
      .from("ams_push_token")
      .select("id")
      .eq("ams_user_id", session.user_id)
      .eq("push_token", token)
      .maybeSingle();

    if (existing?.id) {
      const { error } = await svc.client
        .from("ams_push_token")
        .update({
          ams_company_id: session.company_id,
          device_id: deviceId,
          platform,
          is_enabled: true,
          last_seen_at: now,
          updated_at: now
        })
        .eq("id", existing.id);
      if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });
      return jsonResponse({ ok: true, result: { id: existing.id } });
    }

    const id = crypto.randomUUID();
    const { error } = await svc.client.from("ams_push_token").insert({
      id,
      ams_company_id: session.company_id,
      ams_user_id: session.user_id,
      device_id: deviceId,
      platform,
      push_token: token,
      is_enabled: true,
      last_seen_at: now
    });
    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });
    return jsonResponse({ ok: true, result: { id } });
  }

  if (req.method === "DELETE") {
    const body = await req.json().catch(() => null);
    const token = String(body?.token ?? "").trim();
    if (!token) return jsonResponse({ error: "invalid_body", details: "token_required" }, { status: 400 });

    const { error } = await svc.client
      .from("ams_push_token")
      .update({ is_enabled: false, last_seen_at: new Date().toISOString() })
      .eq("ams_user_id", session.user_id)
      .eq("push_token", token);

    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });
    return jsonResponse({ ok: true, result: { disabled: true } });
  }

  return jsonResponse({ error: "method_not_allowed" }, { status: 405 });
});

