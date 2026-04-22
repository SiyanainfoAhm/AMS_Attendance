import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, jsonResponse, optionsResponse } from "../_shared/http.ts";

type CompanyRow = { id: string; code: string; name: string; is_active: boolean; created_at: string };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse();

  const accessToken = getAmsAccessToken(req);
  if (!accessToken) return jsonResponse({ error: "missing_access_token" }, { status: 401 });

  const svc = tryGetServiceClient();
  if (!svc.ok) return jsonResponse({ error: "server_misconfigured", details: svc.error }, { status: 500 });

  const url = new URL(req.url);
  const page = Math.max(1, Number(url.searchParams.get("page") ?? "1"));
  const pageSize = Math.min(100, Math.max(1, Number(url.searchParams.get("pageSize") ?? "20")));
  const q = (url.searchParams.get("q") ?? "").trim();

  if (req.method === "GET") {
    // Permission check via /me-like logic (reuse permission codes)
    const { data: sess } = await svc.client.rpc("ams_fn_validate_user_session", { p_access_token: accessToken });
    if (!Array.isArray(sess) || sess.length === 0) return jsonResponse({ error: "invalid_session" }, { status: 401 });
    const session = sess[0] as { user_id: string; company_id: string | null };

    const { data: user } = await svc.client
      .from("ams_user")
      .select("id,is_platform_super_admin")
      .eq("id", session.user_id)
      .maybeSingle();
    if (!user) return jsonResponse({ error: "user_not_found" }, { status: 404 });

    if (!user.is_platform_super_admin) {
      const companyId = session.company_id;
      if (!companyId) return jsonResponse({ error: "company_not_selected" }, { status: 403 });
      const { data: perms } = await svc.client.rpc("ams_fn_get_user_permission_codes", {
        p_user_id: session.user_id,
        p_company_id: companyId
      });
      const codes = (perms ?? []).map((r: any) => r.permission_code);
      if (!codes.includes("PLATFORM_COMPANY_READ")) {
        return jsonResponse({ error: "forbidden" }, { status: 403 });
      }
    }

    const from = (page - 1) * pageSize;
    const to = from + pageSize - 1;

    let query = svc.client
      .from("ams_company")
      .select("id,code,name,is_active,created_at", { count: "exact" })
      .order("created_at", { ascending: false });

    if (q) {
      query = query.or(`code.ilike.%${q}%,name.ilike.%${q}%`);
    }

    const { data, error, count } = await query.range(from, to);
    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });

    return jsonResponse({
      ok: true,
      result: {
        items: (data ?? []) as CompanyRow[],
        page,
        pageSize,
        total: count ?? 0
      }
    });
  }

  if (req.method === "POST") {
    let body: any;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "invalid_json" }, { status: 400 });
    }
    const code = typeof body?.code === "string" ? body.code : null;
    const name = typeof body?.name === "string" ? body.name : null;
    const timezone = typeof body?.timezone === "string" ? body.timezone : "Asia/Kolkata";

    const { data, error } = await svc.client.rpc("ams_sp_platform_company_create", {
      p_access_token: accessToken,
      p_code: code,
      p_name: name,
      p_timezone: timezone
    });
    if (error) return jsonResponse({ error: "create_failed", details: error.message }, { status: 400 });
    return jsonResponse({ ok: true, result: data });
  }

  if (req.method === "PATCH") {
    let body: any;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "invalid_json" }, { status: 400 });
    }
    const companyId = typeof body?.companyId === "string" ? body.companyId : null;
    if (!companyId) return jsonResponse({ error: "companyId_required" }, { status: 400 });

    const { data, error } = await svc.client.rpc("ams_sp_platform_company_update", {
      p_access_token: accessToken,
      p_company_id: companyId,
      p_name: typeof body?.name === "string" ? body.name : null,
      p_is_active: typeof body?.isActive === "boolean" ? body.isActive : null
    });
    if (error) return jsonResponse({ error: "update_failed", details: error.message }, { status: 400 });
    return jsonResponse({ ok: true, result: data });
  }

  return jsonResponse({ error: "method_not_allowed" }, { status: 405 });
});

