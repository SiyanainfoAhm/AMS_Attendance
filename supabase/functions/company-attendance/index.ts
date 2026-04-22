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

  const url = new URL(req.url);
  const action = (url.searchParams.get("action") ?? "").trim();

  if (req.method === "POST" && action === "punch") {
    if (!user.is_platform_super_admin) {
      const { data: punchPerms } = await svc.client.rpc("ams_fn_get_user_permission_codes", {
        p_user_id: session.user_id,
        p_company_id: session.company_id
      });
      const punchCodes = (punchPerms ?? []).map((r: { permission_code: string }) => r.permission_code);
      if (!punchCodes.includes("COMPANY_ATTENDANCE_WRITE") && !punchCodes.includes("COMPANY_ATTENDANCE_PUNCH")) {
        return jsonResponse({ error: "forbidden" }, { status: 403 });
      }
    }

    const body = await req.json().catch(() => null);
    const { data, error } = await svc.client.rpc("ams_sp_company_attendance_punch", {
      p_access_token: accessToken,
      p_staff_id: body?.staffId ?? null,
      p_punch_type: body?.punchType ?? null,
      p_station_id: body?.stationId ?? null,
      p_punch_at: body?.punchAt ?? null,
      p_within_geofence: typeof body?.withinGeofence === "boolean" ? body.withinGeofence : null,
      p_face_match_score: body?.faceMatchScore != null ? Number(body.faceMatchScore) : null,
      p_device_id: body?.deviceId ?? null
    });

    if (error) {
      const msg = error.message ?? "";
      if (msg.includes("forbidden")) return jsonResponse({ error: "forbidden" }, { status: 403 });
      if (msg.includes("staff_user_mapping_required")) {
        return jsonResponse({ error: "staff_user_mapping_required", details: msg }, { status: 400 });
      }
      if (msg.includes("forbidden_self_staff_only")) {
        return jsonResponse({ error: "forbidden_self_staff_only", details: msg }, { status: 403 });
      }
      if (msg.includes("staff_id_required")) return jsonResponse({ error: "staff_id_required" }, { status: 400 });
      if (msg.includes("invalid_punch_type")) return jsonResponse({ error: "invalid_punch_type" }, { status: 400 });
      if (msg.includes("staff_not_found")) return jsonResponse({ error: "staff_not_found" }, { status: 400 });
      if (msg.includes("station_not_found")) return jsonResponse({ error: "station_not_found" }, { status: 400 });
      if (msg.includes("device_not_found")) return jsonResponse({ error: "device_not_found" }, { status: 400 });
      if (msg.includes("out_without_in")) {
        return jsonResponse(
          { error: "out_without_in", details: "Punch OUT requires a prior punch IN for this staff member." },
          { status: 400 }
        );
      }
      if (msg.includes("out_not_same_company_day_as_in")) {
        return jsonResponse(
          {
            error: "out_not_same_company_day_as_in",
            details: "Close the prior day with Punch OUT first (legacy rule)."
          },
          { status: 400 }
        );
      }
      return jsonResponse({ error: "punch_failed", details: msg }, { status: 400 });
    }

    return jsonResponse({ ok: true, result: data });
  }

  if (req.method !== "GET") return jsonResponse({ error: "method_not_allowed" }, { status: 405 });

  if (!user.is_platform_super_admin) {
    const { data: perms } = await svc.client.rpc("ams_fn_get_user_permission_codes", {
      p_user_id: session.user_id,
      p_company_id: session.company_id
    });
    const codes = (perms ?? []).map((r: { permission_code: string }) => r.permission_code);
    if (!codes.includes("COMPANY_ATTENDANCE_READ")) return jsonResponse({ error: "forbidden" }, { status: 403 });
  }

  const page = Math.max(1, Number(url.searchParams.get("page") ?? "1"));
  const pageSize = Math.min(200, Math.max(1, Number(url.searchParams.get("pageSize") ?? "50")));
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  const stationId = (url.searchParams.get("stationId") ?? "").trim() || null;
  const staffId = (url.searchParams.get("staffId") ?? "").trim() || null;
  const date = (url.searchParams.get("date") ?? "").trim() || null;
  const include = (url.searchParams.get("include") ?? "").trim();

  let query = svc.client
    .from("ams_attendance_log")
    .select(
      "id,ams_staff_id,ams_station_id,ams_device_id,punch_type,punch_at,within_geofence,face_match_score,created_at",
      { count: "exact" }
    )
    .eq("ams_company_id", session.company_id)
    .order("punch_at", { ascending: false });

  if (stationId) query = query.eq("ams_station_id", stationId);
  if (staffId) query = query.eq("ams_staff_id", staffId);
  if (date) query = query.eq("shift_date", date);

  const { data, error, count } = await query.range(from, to);
  if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });

  // Enrich with geofence name (station-scoped) where possible.
  const stationIds = Array.from(
    new Set((data ?? []).map((r: any) => r.ams_station_id).filter((x: any) => typeof x === "string" && x.length > 0))
  ) as string[];

  let stationGeofenceByStationId = new Map<string, { id: string; name: string | null; center_lat: number | null; center_lng: number | null; radius_m: number | null }>();
  if (stationIds.length > 0) {
    const { data: gfs } = await svc.client
      .from("ams_geofence")
      .select("id,ams_station_id,name,center_lat,center_lng,radius_m,is_active,created_at")
      .eq("ams_company_id", session.company_id)
      .in("ams_station_id", stationIds)
      .eq("is_active", true)
      .order("created_at", { ascending: false });

    for (const g of gfs ?? []) {
      const sid = (g as any).ams_station_id as string | null;
      if (!sid) continue;
      // First one wins due to descending order = latest active.
      if (!stationGeofenceByStationId.has(sid)) {
        stationGeofenceByStationId.set(sid, {
          id: String((g as any).id),
          name: (g as any).name == null ? null : String((g as any).name),
          center_lat: (g as any).center_lat == null ? null : Number((g as any).center_lat),
          center_lng: (g as any).center_lng == null ? null : Number((g as any).center_lng),
          radius_m: (g as any).radius_m == null ? null : Number((g as any).radius_m)
        });
      }
    }
  }

  const items = (data ?? []).map((r: any) => {
    const sid = r.ams_station_id as string | null;
    const gf = sid ? stationGeofenceByStationId.get(sid) : undefined;
    return {
      ...r,
      ams_geofence_id: gf?.id ?? null,
      geofence_name: gf?.name ?? null
    };
  });

  const result: Record<string, unknown> = { items, page, pageSize, total: count ?? 0 };

  if (include === "meta") {
    const [stations, staff] = await Promise.all([
      svc.client
        .from("ams_station")
        .select("id,code,name,is_active,created_at")
        .eq("ams_company_id", session.company_id)
        .order("created_at", { ascending: false }),
      svc.client
        .from("ams_staff")
        .select("id,staff_code,full_name,is_active,created_at")
        .eq("ams_company_id", session.company_id)
        .order("created_at", { ascending: false })
    ]);

    // Attach latest active geofence details to station meta (if available).
    const stationMeta = stations.data ?? [];
    const metaStationIds = stationMeta.map((s: any) => s.id).filter(Boolean);
    let gfByStationId = new Map<string, any>();
    if (metaStationIds.length > 0) {
      const { data: gfs } = await svc.client
        .from("ams_geofence")
        .select("ams_station_id,name,center_lat,center_lng,radius_m,is_active,created_at")
        .eq("ams_company_id", session.company_id)
        .in("ams_station_id", metaStationIds)
        .eq("is_active", true)
        .order("created_at", { ascending: false });
      for (const g of gfs ?? []) {
        const sid = (g as any).ams_station_id as string | null;
        if (!sid) continue;
        if (!gfByStationId.has(sid)) gfByStationId.set(sid, g);
      }
    }

    const stationsWithCoords = stationMeta.map((s: any) => {
      const g = gfByStationId.get(String(s.id));
      return {
        ...s,
        geofenceName: g?.name ?? null,
        latitude: g?.center_lat ?? null,
        longitude: g?.center_lng ?? null,
        radiusM: g?.radius_m ?? null
      };
    });

    result.meta = { stations: stationsWithCoords, staff: staff.data ?? [] };
  }

  return jsonResponse({ ok: true, result });
});
