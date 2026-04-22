import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, jsonResponse, optionsResponse } from "../_shared/http.ts";

type Entity = "zones" | "branches" | "stations" | "geofences";

async function requireCompanyAndPerm(svc: any, accessToken: string, permCode: string) {
  const { data: sess } = await svc.client.rpc("ams_fn_validate_user_session", { p_access_token: accessToken });
  if (!Array.isArray(sess) || sess.length === 0) return { ok: false, status: 401, body: { error: "invalid_session" } };
  const session = sess[0] as { user_id: string; company_id: string | null };
  if (!session.company_id) return { ok: false, status: 403, body: { error: "company_not_selected" } };

  const { data: user } = await svc.client
    .from("ams_user")
    .select("id,is_platform_super_admin")
    .eq("id", session.user_id)
    .maybeSingle();
  if (!user) return { ok: false, status: 404, body: { error: "user_not_found" } };
  if (user.is_platform_super_admin) return { ok: true, session };

  const { data: perms } = await svc.client.rpc("ams_fn_get_user_permission_codes", {
    p_user_id: session.user_id,
    p_company_id: session.company_id
  });
  const codes = (perms ?? []).map((r: any) => r.permission_code);
  if (!codes.includes(permCode)) return { ok: false, status: 403, body: { error: "forbidden" } };
  return { ok: true, session };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse();

  const accessToken = getAmsAccessToken(req);
  if (!accessToken) return jsonResponse({ error: "missing_access_token" }, { status: 401 });

  const svc = tryGetServiceClient();
  if (!svc.ok) return jsonResponse({ error: "server_misconfigured", details: svc.error }, { status: 500 });

  const url = new URL(req.url);
  const entity = (url.searchParams.get("entity") ?? "").trim() as Entity;
  const action = (url.searchParams.get("action") ?? "").trim().toLowerCase();
  if (!["zones", "branches", "stations", "geofences"].includes(entity)) {
    return jsonResponse({ error: "invalid_entity" }, { status: 400 });
  }

  if (req.method === "GET") {
    const guard = await requireCompanyAndPerm(svc, accessToken, "COMPANY_ORG_READ");
    if (!guard.ok) return jsonResponse(guard.body, { status: guard.status });
    const companyId = guard.session.company_id as string;

    const q = (url.searchParams.get("q") ?? "").trim();
    const page = Math.max(1, Number(url.searchParams.get("page") ?? "1"));
    const pageSize = Math.min(100, Math.max(1, Number(url.searchParams.get("pageSize") ?? "50")));
    const from = (page - 1) * pageSize;
    const to = from + pageSize - 1;

    const table =
      entity === "zones"
        ? "ams_zone"
        : entity === "branches"
          ? "ams_branch"
          : entity === "stations"
            ? "ams_station"
            : "ams_geofence";

    let selectCols = "*";
    if (entity === "zones") selectCols = "id,code,name,description,is_active,created_at";
    if (entity === "branches") selectCols = "id,ams_zone_id,code,name,is_active,created_at";
    if (entity === "stations") selectCols = "id,ams_zone_id,ams_branch_id,code,name,is_active,created_at";
    if (entity === "geofences")
      selectCols = "id,ams_station_id,code,name,geofence_type,center_lat,center_lng,radius_m,is_active,created_at";

    let query = svc.client
      .from(table)
      .select(selectCols, { count: "exact" })
      .eq("ams_company_id", companyId)
      .order("created_at", { ascending: false });

    if (q) query = query.or(`code.ilike.%${q}%,name.ilike.%${q}%`);

    const { data, error, count } = await query.range(from, to);
    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });

    return jsonResponse({ ok: true, result: { items: data ?? [], page, pageSize, total: count ?? 0 } });
  }

  if (req.method === "POST") {
    const guard = await requireCompanyAndPerm(svc, accessToken, "COMPANY_ORG_WRITE");
    if (!guard.ok) return jsonResponse(guard.body, { status: guard.status });

    let body: any;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "invalid_json" }, { status: 400 });
    }

    const bodyHasUpdateId = typeof body?.id === "string" && body.id.trim().length > 0;
    const explicitCreate = action === "create";
    const explicitUpdate = action === "update";
    // If `action=update` is dropped by a proxy/client bug, a body with `id` must not hit create (e.g. zone_code_required).
    const isPostUpdate = explicitUpdate || (!explicitCreate && bodyHasUpdateId);

    // Prefer POST for updates (more reliable across browsers/proxies than PATCH).
    if (isPostUpdate) {
      if (entity === "zones") {
        const { data, error } = await svc.client.rpc("ams_sp_company_zone_update", {
          p_access_token: accessToken,
          p_zone_id: body?.id ?? null,
          p_name: body?.name ?? null,
          p_description: body?.description ?? null,
          p_is_active: typeof body?.isActive === "boolean" ? body.isActive : null
        });
        if (error) return jsonResponse({ error: "update_failed", details: error.message }, { status: 400 });
        return jsonResponse({ ok: true, result: data });
      }
      if (entity === "branches") {
        const { data, error } = await svc.client.rpc("ams_sp_company_branch_update", {
          p_access_token: accessToken,
          p_branch_id: body?.id ?? null,
          p_is_active: typeof body?.isActive === "boolean" ? body.isActive : null,
          p_name: body?.name ?? null,
          p_zone_id: body?.zoneId ?? null
        });
        if (error) return jsonResponse({ error: "update_failed", details: error.message }, { status: 400 });
        return jsonResponse({ ok: true, result: data });
      }
      if (entity === "stations") {
        const { data, error } = await svc.client.rpc("ams_sp_company_station_update", {
          p_access_token: accessToken,
          p_station_id: body?.id ?? null,
          p_zone_id: body?.zoneId ?? null,
          p_branch_id: body?.branchId ?? null,
          p_name: body?.name ?? null,
          p_is_active: typeof body?.isActive === "boolean" ? body.isActive : null
        });
        if (error) return jsonResponse({ error: "update_failed", details: error.message }, { status: 400 });
        return jsonResponse({ ok: true, result: data });
      }
      if (entity === "geofences") {
        const { data, error } = await svc.client.rpc("ams_sp_company_geofence_update", {
          p_access_token: accessToken,
          p_geofence_id: body?.id ?? null,
          p_station_id: body?.stationId ?? null,
          p_name: body?.name ?? null,
          p_is_active: typeof body?.isActive === "boolean" ? body.isActive : null,
          p_center_lat: body?.centerLat ?? null,
          p_center_lng: body?.centerLng ?? null,
          p_radius_m: body?.radiusM ?? null
        });
        if (error) return jsonResponse({ error: "update_failed", details: error.message }, { status: 400 });
        return jsonResponse({ ok: true, result: data });
      }
    }

    if (entity === "zones") {
      const { data, error } = await svc.client.rpc("ams_sp_company_zone_create", {
        p_access_token: accessToken,
        p_code: body?.code ?? null,
        p_name: body?.name ?? null,
        p_description: body?.description ?? null
      });
      if (error) return jsonResponse({ error: "create_failed", details: error.message }, { status: 400 });
      return jsonResponse({ ok: true, result: data });
    }
    if (entity === "branches") {
      const { data, error } = await svc.client.rpc("ams_sp_company_branch_create", {
        p_access_token: accessToken,
        p_code: body?.code ?? null,
        p_name: body?.name ?? null,
        p_zone_id: body?.zoneId ?? null
      });
      if (error) return jsonResponse({ error: "create_failed", details: error.message }, { status: 400 });
      return jsonResponse({ ok: true, result: data });
    }
    if (entity === "stations") {
      const { data, error } = await svc.client.rpc("ams_sp_company_station_create", {
        p_access_token: accessToken,
        p_code: body?.code ?? null,
        p_name: body?.name ?? null,
        p_branch_id: body?.branchId ?? null,
        p_zone_id: body?.zoneId ?? null
      });
      if (error) return jsonResponse({ error: "create_failed", details: error.message }, { status: 400 });
      return jsonResponse({ ok: true, result: data });
    }
    if (entity === "geofences") {
      const { data, error } = await svc.client.rpc("ams_sp_company_geofence_create", {
        p_access_token: accessToken,
        p_code: body?.code ?? null,
        p_name: body?.name ?? null,
        p_geofence_type: body?.geofenceType ?? "circle",
        p_station_id: body?.stationId ?? null,
        p_center_lat: body?.centerLat ?? null,
        p_center_lng: body?.centerLng ?? null,
        p_radius_m: body?.radiusM ?? null,
        p_polygon_json: body?.polygonJson ?? []
      });
      if (error) return jsonResponse({ error: "create_failed", details: error.message }, { status: 400 });
      return jsonResponse({ ok: true, result: data });
    }
  }

  if (req.method === "PATCH") {
    const guard = await requireCompanyAndPerm(svc, accessToken, "COMPANY_ORG_WRITE");
    if (!guard.ok) return jsonResponse(guard.body, { status: guard.status });

    let body: any;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "invalid_json" }, { status: 400 });
    }

    if (entity === "zones") {
      const { data, error } = await svc.client.rpc("ams_sp_company_zone_update", {
        p_access_token: accessToken,
        p_zone_id: body?.id ?? null,
        p_name: body?.name ?? null,
        p_description: body?.description ?? null,
        p_is_active: typeof body?.isActive === "boolean" ? body.isActive : null
      });
      if (error) return jsonResponse({ error: "update_failed", details: error.message }, { status: 400 });
      return jsonResponse({ ok: true, result: data });
    }
    if (entity === "branches") {
      const { data, error } = await svc.client.rpc("ams_sp_company_branch_update", {
        p_access_token: accessToken,
        p_branch_id: body?.id ?? null,
        p_is_active: typeof body?.isActive === "boolean" ? body.isActive : null,
        p_name: body?.name ?? null,
        p_zone_id: body?.zoneId ?? null
      });
      if (error) return jsonResponse({ error: "update_failed", details: error.message }, { status: 400 });
      return jsonResponse({ ok: true, result: data });
    }
    if (entity === "stations") {
      const { data, error } = await svc.client.rpc("ams_sp_company_station_update", {
        p_access_token: accessToken,
        p_station_id: body?.id ?? null,
        p_zone_id: body?.zoneId ?? null,
        p_branch_id: body?.branchId ?? null,
        p_name: body?.name ?? null,
        p_is_active: typeof body?.isActive === "boolean" ? body.isActive : null
      });
      if (error) return jsonResponse({ error: "update_failed", details: error.message }, { status: 400 });
      return jsonResponse({ ok: true, result: data });
    }
    if (entity === "geofences") {
      const { data, error } = await svc.client.rpc("ams_sp_company_geofence_update", {
        p_access_token: accessToken,
        p_geofence_id: body?.id ?? null,
        p_station_id: body?.stationId ?? null,
        p_name: body?.name ?? null,
        p_is_active: typeof body?.isActive === "boolean" ? body.isActive : null,
        p_center_lat: body?.centerLat ?? null,
        p_center_lng: body?.centerLng ?? null,
        p_radius_m: body?.radiusM ?? null
      });
      if (error) return jsonResponse({ error: "update_failed", details: error.message }, { status: 400 });
      return jsonResponse({ ok: true, result: data });
    }
  }

  return jsonResponse({ error: "method_not_allowed" }, { status: 405 });
});

