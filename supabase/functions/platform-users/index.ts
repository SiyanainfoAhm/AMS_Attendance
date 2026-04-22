import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, jsonResponse, optionsResponse } from "../_shared/http.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse();

  const accessToken = getAmsAccessToken(req);
  if (!accessToken) return jsonResponse({ error: "missing_access_token" }, { status: 401 });

  const svc = tryGetServiceClient();
  if (!svc.ok) return jsonResponse({ error: "server_misconfigured", details: svc.error }, { status: 500 });

  // session + actor
  const { data: sess } = await svc.client.rpc("ams_fn_validate_user_session", { p_access_token: accessToken });
  if (!Array.isArray(sess) || sess.length === 0) return jsonResponse({ error: "invalid_session" }, { status: 401 });
  const session = sess[0] as { user_id: string; company_id: string | null };

  const { data: actor } = await svc.client
    .from("ams_user")
    .select("id,is_platform_super_admin,is_active")
    .eq("id", session.user_id)
    .maybeSingle();
  if (!actor) return jsonResponse({ error: "user_not_found" }, { status: 404 });

  async function requirePerm(code: string) {
    if (actor.is_platform_super_admin) return;
    const companyId = session.company_id;
    if (!companyId) throw new Error("company_not_selected");
    const { data: perms } = await svc.client.rpc("ams_fn_get_user_permission_codes", {
      p_user_id: session.user_id,
      p_company_id: companyId
    });
    const codes = (perms ?? []).map((r: any) => r.permission_code);
    if (!codes.includes(code)) throw new Error("forbidden");
  }

  const url = new URL(req.url);
  const action = (url.searchParams.get("action") ?? "").trim();

  if (req.method === "GET" && action === "list-company-maps") {
    await requirePerm("PLATFORM_USER_READ");
    const userId = (url.searchParams.get("userId") ?? "").trim();
    if (!userId) return jsonResponse({ error: "invalid_query", details: "userId_required" }, { status: 400 });

    const { data, error } = await svc.client
      .from("ams_user_company_map")
      .select("ams_company_id,is_active,updated_at,ams_company:ams_company_id(id,code,name,is_active)")
      .eq("ams_user_id", userId)
      .order("updated_at", { ascending: false });

    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });
    const seen = new Set<string>();
    const items = (data ?? [])
      .map((r: any) => ({
        companyId: String(r?.ams_company_id ?? r?.AMS_company_id ?? "").trim(),
        isActive: typeof r?.is_active === "boolean" ? r.is_active : true,
        updatedAt: r?.updated_at ?? null,
        company: r?.ams_company ?? null
      }))
      .filter((r: any) => r.companyId.length > 0)
      .filter((r: any) => {
        if (seen.has(r.companyId)) return false;
        seen.add(r.companyId);
        return true;
      });

    return jsonResponse({ ok: true, result: { items } });
  }

  if (req.method === "GET" && action === "list-role-maps") {
    await requirePerm("PLATFORM_USER_READ");
    const userId = (url.searchParams.get("userId") ?? "").trim();
    if (!userId) return jsonResponse({ error: "invalid_query", details: "userId_required" }, { status: 400 });

    const { data, error } = await svc.client
      .from("ams_user_role_map")
      .select(
        "ams_role_id,ams_company_id,is_active,updated_at,ams_role:ams_role_id(id,code,name,is_active,is_platform_role,ams_company_id)",
      )
      .eq("ams_user_id", userId)
      .order("updated_at", { ascending: false });

    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });
    const seen = new Set<string>();
    const items = (data ?? [])
      .map((r: any) => {
        const roleId = String(r?.ams_role_id ?? "").trim();
        const companyId = r?.ams_company_id == null ? null : String(r.ams_company_id);
        const key = `${roleId}:${companyId ?? ""}`;
        return {
          roleId,
          companyId,
          isActive: typeof r?.is_active === "boolean" ? r.is_active : true,
          updatedAt: r?.updated_at ?? null,
          role: r?.ams_role ?? null,
        };
      })
      .filter((r: any) => r.roleId.length > 0)
      .filter((r: any) => {
        const key = `${r.roleId}:${r.companyId ?? ""}`;
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
      });

    return jsonResponse({ ok: true, result: { items } });
  }

  if (req.method === "GET") {
    await requirePerm("PLATFORM_USER_READ");
    const page = Math.max(1, Number(url.searchParams.get("page") ?? "1"));
    const pageSize = Math.min(100, Math.max(1, Number(url.searchParams.get("pageSize") ?? "20")));
    const q = (url.searchParams.get("q") ?? "").trim();
    const include = (url.searchParams.get("include") ?? "").trim();

    const from = (page - 1) * pageSize;
    const to = from + pageSize - 1;

    let query = svc.client
      .from("ams_user")
      .select("id,display_name,email,is_active,is_platform_super_admin,created_at", { count: "exact" })
      .order("created_at", { ascending: false });

    if (q) query = query.or(`email.ilike.%${q}%,display_name.ilike.%${q}%`);

    const { data, error, count } = await query.range(from, to);
    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });

    const result: any = { items: data ?? [], page, pageSize, total: count ?? 0 };

    if (include === "meta") {
      const { data: companies } = await svc.client
        .from("ams_company")
        .select("id,code,name,is_active,created_at")
        .order("created_at", { ascending: false });

      const { data: roles } = await svc.client
        .from("ams_role")
        .select("id,ams_company_id,code,name,is_active,is_platform_role")
        .order("code", { ascending: true });

      result.meta = { companies: companies ?? [], roles: roles ?? [] };
    }

    return jsonResponse({ ok: true, result });
  }

  if (req.method === "POST" && action === "create") {
    await requirePerm("PLATFORM_USER_WRITE");
    let body: any;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "invalid_json" }, { status: 400 });
    }
    const { data, error } = await svc.client.rpc("ams_sp_platform_user_create", {
      p_access_token: accessToken,
      p_display_name: body?.displayName ?? null,
      p_email: body?.email ?? null,
      p_password: body?.password ?? null,
      p_is_platform_super_admin: body?.isPlatformSuperAdmin ?? false
    });
    if (error) return jsonResponse({ error: "create_failed", details: error.message }, { status: 400 });
    return jsonResponse({ ok: true, result: data });
  }

  if (req.method === "POST" && action === "update") {
    await requirePerm("PLATFORM_USER_WRITE");
    let body: any;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "invalid_json" }, { status: 400 });
    }
    const { data, error } = await svc.client.rpc("ams_sp_platform_user_update", {
      p_access_token: accessToken,
      p_user_id: body?.userId ?? null,
      p_display_name: body?.displayName ?? null,
      p_email: body?.email ?? null,
      p_password: body?.password ?? null,
      p_is_platform_super_admin: typeof body?.isPlatformSuperAdmin === "boolean" ? body.isPlatformSuperAdmin : null,
      p_is_active: typeof body?.isActive === "boolean" ? body.isActive : null
    });
    if (error) return jsonResponse({ error: "update_failed", details: error.message }, { status: 400 });
    return jsonResponse({ ok: true, result: data });
  }

  if (req.method === "POST" && action === "set-active") {
    await requirePerm("PLATFORM_USER_WRITE");
    let body: any;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "invalid_json" }, { status: 400 });
    }
    const { data, error } = await svc.client.rpc("ams_sp_platform_user_set_active", {
      p_access_token: accessToken,
      p_user_id: body?.userId ?? null,
      p_is_active: body?.isActive ?? null
    });
    if (error) return jsonResponse({ error: "update_failed", details: error.message }, { status: 400 });
    return jsonResponse({ ok: true, result: data });
  }

  if (req.method === "POST" && action === "map-company") {
    await requirePerm("PLATFORM_USER_WRITE");
    let body: any;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "invalid_json" }, { status: 400 });
    }
    const { data, error } = await svc.client.rpc("ams_sp_platform_user_map_company", {
      p_access_token: accessToken,
      p_user_id: body?.userId ?? null,
      p_company_id: body?.companyId ?? null,
      p_is_active: body?.isActive ?? true
    });
    if (error) return jsonResponse({ error: "map_failed", details: error.message }, { status: 400 });
    return jsonResponse({ ok: true, result: data });
  }

  if (req.method === "POST" && action === "assign-role") {
    await requirePerm("PLATFORM_USER_WRITE");
    let body: any;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "invalid_json" }, { status: 400 });
    }
    const { data, error } = await svc.client.rpc("ams_sp_platform_user_assign_role", {
      p_access_token: accessToken,
      p_user_id: body?.userId ?? null,
      p_role_id: body?.roleId ?? null,
      p_company_id: body?.companyId ?? null,
      p_is_active: body?.isActive ?? true
    });
    if (error) return jsonResponse({ error: "assign_failed", details: error.message }, { status: 400 });
    return jsonResponse({ ok: true, result: data });
  }

  return jsonResponse({ error: "method_not_allowed" }, { status: 405 });
});

