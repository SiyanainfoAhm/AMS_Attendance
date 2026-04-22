import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, jsonResponse, optionsResponse } from "../_shared/http.ts";

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

  const { data: user } = await svc.client
    .from("ams_user")
    .select("id,is_platform_super_admin")
    .eq("id", session.user_id)
    .maybeSingle();
  if (!user) return jsonResponse({ error: "user_not_found" }, { status: 404 });

  async function requirePerm(code: string) {
    if (user.is_platform_super_admin) return;
    const { data: perms } = await svc.client.rpc("ams_fn_get_user_permission_codes", {
      p_user_id: session.user_id,
      p_company_id: session.company_id
    });
    const codes = (perms ?? []).map((r: any) => r.permission_code);
    if (!codes.includes(code)) throw new Error("forbidden");
  }

  const url = new URL(req.url);
  const action = (url.searchParams.get("action") ?? "").trim();

  if (req.method === "GET" && action === "list-station-maps") {
    await requirePerm("COMPANY_STAFF_READ");
    const staffId = (url.searchParams.get("staffId") ?? "").trim();
    if (!staffId) return jsonResponse({ error: "invalid_query", details: "staffId_required" }, { status: 400 });

    const { data, error } = await svc.client
      .from("ams_staff_station_map")
      .select("ams_station_id,is_active,is_primary,updated_at,ams_station:ams_station_id(id,code,name,is_active)")
      .eq("ams_company_id", session.company_id)
      .eq("ams_staff_id", staffId)
      .order("updated_at", { ascending: false });

    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });

    const seen = new Set<string>();
    const items = (data ?? [])
      .map((r: any) => ({
        stationId: String(r?.ams_station_id ?? "").trim(),
        isActive: typeof r?.is_active === "boolean" ? r.is_active : true,
        isPrimary: Boolean(r?.is_primary),
        updatedAt: r?.updated_at ?? null,
        station: r?.ams_station ?? null
      }))
      .filter((r: any) => r.stationId.length > 0)
      .filter((r: any) => {
        if (seen.has(r.stationId)) return false;
        seen.add(r.stationId);
        return true;
      });

    return jsonResponse({ ok: true, result: { items } });
  }

  if (req.method === "GET" && action === "list-user-links") {
    await requirePerm("COMPANY_STAFF_READ");
    const staffId = (url.searchParams.get("staffId") ?? "").trim();
    if (!staffId) return jsonResponse({ error: "invalid_query", details: "staffId_required" }, { status: 400 });

    const { data, error } = await svc.client
      .from("ams_user_staff_map")
      .select("ams_user_id,is_active,updated_at,ams_user:ams_user_id(id,display_name,email,is_active)")
      .eq("ams_company_id", session.company_id)
      .eq("ams_staff_id", staffId)
      .order("updated_at", { ascending: false });

    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });

    const items =
      (data ?? []).map((r: any) => ({
        userId: String(r?.ams_user_id ?? "").trim(),
        isActive: typeof r?.is_active === "boolean" ? r.is_active : true,
        updatedAt: r?.updated_at ?? null,
        user: r?.ams_user ?? null,
      })) ?? [];

    return jsonResponse({ ok: true, result: { items } });
  }

  if (req.method === "GET") {
    await requirePerm("COMPANY_STAFF_READ");
    const page = Math.max(1, Number(url.searchParams.get("page") ?? "1"));
    const pageSize = Math.min(100, Math.max(1, Number(url.searchParams.get("pageSize") ?? "25")));
    const q = (url.searchParams.get("q") ?? "").trim();
    const include = (url.searchParams.get("include") ?? "").trim();

    const from = (page - 1) * pageSize;
    const to = from + pageSize - 1;

    let query = svc.client
      .from("ams_staff")
      .select("id,staff_code,full_name,mobile,email,status,is_active,created_at", { count: "exact" })
      .eq("ams_company_id", session.company_id)
      .order("created_at", { ascending: false });

    if (q) query = query.or(`staff_code.ilike.%${q}%,full_name.ilike.%${q}%,mobile.ilike.%${q}%`);

    const { data, error, count } = await query.range(from, to);
    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });

    const result: any = { items: data ?? [], page, pageSize, total: count ?? 0 };

    if (include === "meta") {
      const { data: stations } = await svc.client
        .from("ams_station")
        .select("id,code,name,is_active,created_at")
        .eq("ams_company_id", session.company_id)
        .order("created_at", { ascending: false });

      const { data: users } = await svc.client
        .from("ams_user_company_map")
        .select("ams_user_id, ams_user(display_name,email)")
        .eq("ams_company_id", session.company_id)
        .eq("is_active", true);

      result.meta = {
        stations: stations ?? [],
        users:
          (users ?? []).map((r: any) => ({
            id: r.ams_user_id,
            displayName: r.ams_user?.display_name ?? null,
            email: r.ams_user?.email ?? null
          })) ?? []
      };
    }

    return jsonResponse({ ok: true, result });
  }

  if (req.method === "POST" && action === "create") {
    await requirePerm("COMPANY_STAFF_WRITE");
    const body = await req.json().catch(() => null);
    const { data, error } = await svc.client.rpc("ams_sp_company_staff_create", {
      p_access_token: accessToken,
      p_staff_code: body?.staffCode ?? null,
      p_full_name: body?.fullName ?? null,
      p_mobile: body?.mobile ?? null,
      p_email: body?.email ?? null
    });
    if (error) return jsonResponse({ error: "create_failed", details: error.message }, { status: 400 });
    return jsonResponse({ ok: true, result: data });
  }

  if (req.method === "POST" && action === "update") {
    await requirePerm("COMPANY_STAFF_WRITE");
    const body = await req.json().catch(() => null);
    const { data, error } = await svc.client.rpc("ams_sp_company_staff_update", {
      p_access_token: accessToken,
      p_staff_id: body?.staffId ?? null,
      p_full_name: body?.fullName ?? null,
      p_mobile: body?.mobile ?? null,
      p_email: body?.email ?? null,
      p_status: body?.status ?? null,
      p_is_active: typeof body?.isActive === "boolean" ? body.isActive : null
    });
    if (error) return jsonResponse({ error: "update_failed", details: error.message }, { status: 400 });
    return jsonResponse({ ok: true, result: data });
  }

  if (req.method === "POST" && action === "map-station") {
    await requirePerm("COMPANY_STAFF_WRITE");
    const body = await req.json().catch(() => null);
    const { data, error } = await svc.client.rpc("ams_sp_company_staff_map_station", {
      p_access_token: accessToken,
      p_staff_id: body?.staffId ?? null,
      p_station_id: body?.stationId ?? null,
      p_is_primary: body?.isPrimary ?? false,
      p_is_active: body?.isActive ?? true
    });
    if (error) return jsonResponse({ error: "map_failed", details: error.message }, { status: 400 });
    return jsonResponse({ ok: true, result: data });
  }

  if (req.method === "POST" && action === "add-document") {
    await requirePerm("COMPANY_STAFF_WRITE");
    const body = await req.json().catch(() => null);
    const { data, error } = await svc.client.rpc("ams_sp_company_staff_add_document", {
      p_access_token: accessToken,
      p_staff_id: body?.staffId ?? null,
      p_document_type: body?.documentType ?? null,
      p_document_number: body?.documentNumber ?? null,
      p_storage_bucket: body?.storageBucket ?? null,
      p_storage_path: body?.storagePath ?? null,
      p_issued_at: body?.issuedAt ?? null,
      p_expires_at: body?.expiresAt ?? null
    });
    if (error) return jsonResponse({ error: "document_failed", details: error.message }, { status: 400 });
    return jsonResponse({ ok: true, result: data });
  }

  if (req.method === "POST" && action === "map-user") {
    await requirePerm("COMPANY_STAFF_WRITE");
    const body = await req.json().catch(() => null);
    const { data, error } = await svc.client.rpc("ams_sp_company_user_staff_map_upsert", {
      p_access_token: accessToken,
      p_user_id: body?.userId ?? null,
      p_staff_id: body?.staffId ?? null,
      p_is_active: typeof body?.isActive === "boolean" ? body.isActive : true
    });
    if (error) return jsonResponse({ error: "map_user_failed", details: error.message }, { status: 400 });
    return jsonResponse({ ok: true, result: data });
  }

  return jsonResponse({ error: "method_not_allowed" }, { status: 405 });
});

