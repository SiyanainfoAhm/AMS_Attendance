import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, jsonResponse, optionsResponse } from "../_shared/http.ts";

const STATUSES = ["queued", "sent", "failed", "read"] as const;

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

  if (req.method === "GET") {
    const page = Math.max(1, Number(url.searchParams.get("page") ?? "1"));
    const pageSize = Math.min(100, Math.max(1, Number(url.searchParams.get("pageSize") ?? "25")));
    const statusFilter = (url.searchParams.get("status") ?? "").trim();
    const onlyUnread = (url.searchParams.get("unread") ?? "").trim() === "1";
    const from = (page - 1) * pageSize;
    const to = from + pageSize - 1;

    let query = svc.client
      .from("ams_notification")
      .select("id,notif_type,title,body,payload_json,status,channel,priority,sent_at,read_at,created_at", { count: "exact" })
      .eq("ams_company_id", session.company_id)
      .eq("ams_user_id", session.user_id)
      .order("created_at", { ascending: false });

    if (onlyUnread) query = query.is("read_at", null);
    if (statusFilter && (STATUSES as readonly string[]).includes(statusFilter)) query = query.eq("status", statusFilter);

    const { data, error, count } = await query.range(from, to);
    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });
    return jsonResponse({ ok: true, result: { items: data ?? [], page, pageSize, total: count ?? 0 } });
  }

  if (req.method === "POST" && action === "mark-read") {
    const body = await req.json().catch(() => null);
    const id = String(body?.id ?? "").trim();
    if (!id) return jsonResponse({ error: "invalid_body", details: "id_required" }, { status: 400 });

    const now = new Date().toISOString();
    const { data, error } = await svc.client
      .from("ams_notification")
      .update({ read_at: now, status: "read", updated_at: now })
      .eq("id", id)
      .eq("ams_company_id", session.company_id)
      .eq("ams_user_id", session.user_id)
      .select("id,read_at,status")
      .maybeSingle();

    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });
    if (!data) return jsonResponse({ error: "not_found" }, { status: 404 });
    return jsonResponse({ ok: true, result: data });
  }

  if (req.method === "POST" && action === "mark-all-read") {
    const now = new Date().toISOString();
    const { error } = await svc.client
      .from("ams_notification")
      .update({ read_at: now, status: "read", updated_at: now })
      .eq("ams_company_id", session.company_id)
      .eq("ams_user_id", session.user_id)
      .is("read_at", null);

    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });
    return jsonResponse({ ok: true, result: { ok: true } });
  }

  return jsonResponse({ error: "method_not_allowed" }, { status: 405 });
});

