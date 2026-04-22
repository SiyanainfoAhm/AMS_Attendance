import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, jsonResponse, mergeResponseHeaders, optionsResponse } from "../_shared/http.ts";
import { logAmsEdge } from "../_shared/ams_log.ts";

/** Default range for productivity / station summary (views). */
const MAX_RANGE_DAYS = 366;
/** Daily attendance RPC aggregates per staff-day; keep bounded for latency and DB load. */
const MAX_RANGE_DAYS_DAILY_ATTENDANCE = 93;
/** Above this span, successful daily_attendance responses include X-AMS-Report-Warning. */
const WARN_DAILY_SPAN_DAYS = 31;

function parseISODateDay(s: string | null): Date | null {
  if (!s || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const d = new Date(`${s}T00:00:00.000Z`);
  return Number.isNaN(d.getTime()) ? null : d;
}

function utcDayStart(d: Date): string {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 0, 0, 0, 0)).toISOString();
}

function utcDayEndIso(yyyyMmDd: string): string {
  const d = new Date(`${yyyyMmDd}T23:59:59.999Z`);
  return d.toISOString();
}

function fmtUtc(d: Date): string {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;
}

function reqIdHeaders(requestId: string, extra?: HeadersInit): Headers {
  return mergeResponseHeaders(extra, { "X-AMS-Request-Id": requestId });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse();
  if (req.method !== "GET") return jsonResponse({ error: "method_not_allowed" }, { status: 405 });

  const requestId = crypto.randomUUID();

  const accessToken = getAmsAccessToken(req);
  if (!accessToken) {
    return jsonResponse({ error: "missing_access_token", request_id: requestId }, { status: 401, headers: reqIdHeaders(requestId) });
  }

  const svc = tryGetServiceClient();
  if (!svc.ok) {
    logAmsEdge("company-reports", "error", { request_id: requestId, outcome: "server_misconfigured", details: svc.error });
    return jsonResponse({ error: "server_misconfigured", request_id: requestId, details: svc.error }, { status: 500, headers: reqIdHeaders(requestId) });
  }

  const { data: sess } = await svc.client.rpc("ams_fn_validate_user_session", { p_access_token: accessToken });
  if (!Array.isArray(sess) || sess.length === 0) {
    return jsonResponse({ error: "invalid_session", request_id: requestId }, { status: 401, headers: reqIdHeaders(requestId) });
  }
  const session = sess[0] as { user_id: string; company_id: string | null };
  if (!session.company_id) {
    return jsonResponse({ error: "company_not_selected", request_id: requestId }, { status: 403, headers: reqIdHeaders(requestId) });
  }

  const { data: user } = await svc.client
    .from("ams_user")
    .select("id,is_platform_super_admin")
    .eq("id", session.user_id)
    .maybeSingle();
  if (!user) {
    return jsonResponse({ error: "user_not_found", request_id: requestId }, { status: 404, headers: reqIdHeaders(requestId) });
  }

  if (!user.is_platform_super_admin) {
    const { data: perms } = await svc.client.rpc("ams_fn_get_user_permission_codes", {
      p_user_id: session.user_id,
      p_company_id: session.company_id
    });
    const codes = (perms ?? []).map((r: { permission_code: string }) => r.permission_code);
    if (!codes.includes("COMPANY_REPORT_READ")) {
      return jsonResponse({ error: "forbidden", request_id: requestId }, { status: 403, headers: reqIdHeaders(requestId) });
    }
  }

  const url = new URL(req.url);
  const report = (url.searchParams.get("report") ?? "").trim();
  const fromParam = (url.searchParams.get("from") ?? "").trim();
  const toParam = (url.searchParams.get("to") ?? "").trim();

  const toD = parseISODateDay(toParam) ?? new Date();
  let fromD = parseISODateDay(fromParam) ?? new Date(toD.getTime() - 29 * 86400000);
  if (fromD > toD) {
    return jsonResponse({ error: "invalid_range", code: "from_after_to", request_id: requestId }, { status: 400, headers: reqIdHeaders(requestId) });
  }

  const spanDays = Math.ceil((toD.getTime() - fromD.getTime()) / 86400000) + 1;
  if (spanDays > MAX_RANGE_DAYS) {
    logAmsEdge("company-reports", "warn", {
      request_id: requestId,
      company_id: session.company_id,
      user_id: session.user_id,
      report: report || "summary",
      outcome: "range_exceeds_max",
      span_days: spanDays,
      max_days: MAX_RANGE_DAYS
    });
    return jsonResponse(
      {
        error: "invalid_range",
        code: "range_exceeds_max",
        details: `max_${MAX_RANGE_DAYS}_days`,
        max_days: MAX_RANGE_DAYS,
        request_id: requestId
      },
      { status: 400, headers: reqIdHeaders(requestId) }
    );
  }

  if (report === "daily_attendance" && spanDays > MAX_RANGE_DAYS_DAILY_ATTENDANCE) {
    logAmsEdge("company-reports", "warn", {
      request_id: requestId,
      company_id: session.company_id,
      user_id: session.user_id,
      report: "daily_attendance",
      outcome: "range_exceeds_daily_max",
      span_days: spanDays,
      max_days: MAX_RANGE_DAYS_DAILY_ATTENDANCE
    });
    return jsonResponse(
      {
        error: "invalid_range",
        code: "range_exceeds_max",
        details: `daily_attendance_max_${MAX_RANGE_DAYS_DAILY_ATTENDANCE}_days`,
        max_days: MAX_RANGE_DAYS_DAILY_ATTENDANCE,
        report: "daily_attendance",
        request_id: requestId
      },
      { status: 400, headers: reqIdHeaders(requestId) }
    );
  }

  const fromIso = utcDayStart(fromD);
  const toIso = utcDayEndIso(fmtUtc(toD));

  // Phase 7: Daily attendance rollup report (fast reporting, server-side refresh).
  if (report === "daily_attendance") {
    const staffId = (url.searchParams.get("staffId") ?? "").trim() || null;
    const stationId = (url.searchParams.get("stationId") ?? "").trim() || null;
    const t0 = performance.now();
    let data: unknown;
    let rpcError: { message: string; code?: string } | null = null;
    try {
      const res = await svc.client.rpc("ams_sp_company_attendance_daily_report", {
        p_access_token: accessToken,
        p_from: fmtUtc(fromD),
        p_to: fmtUtc(toD),
        p_staff_id: staffId,
        p_station_id: stationId
      });
      data = res.data;
      rpcError = res.error ?? null;
    } catch (e) {
      const durationMs = Math.round(performance.now() - t0);
      const err = e instanceof Error ? e.message : String(e);
      logAmsEdge("company-reports", "error", {
        request_id: requestId,
        company_id: session.company_id,
        user_id: session.user_id,
        report: "daily_attendance",
        outcome: "rpc_exception",
        span_days: spanDays,
        duration_ms: durationMs,
        message: err
      });
      return jsonResponse(
        {
          error: "report_failed",
          code: "report_rpc_failed",
          request_id: requestId
        },
        { status: 502, headers: reqIdHeaders(requestId) }
      );
    }

    const durationMs = Math.round(performance.now() - t0);
    if (rpcError) {
      logAmsEdge("company-reports", "error", {
        request_id: requestId,
        company_id: session.company_id,
        user_id: session.user_id,
        report: "daily_attendance",
        outcome: "rpc_error",
        span_days: spanDays,
        duration_ms: durationMs,
        rpc_message: rpcError.message,
        rpc_code: rpcError.code
      });
      return jsonResponse(
        {
          error: "report_failed",
          code: "report_rpc_failed",
          request_id: requestId
        },
        { status: 502, headers: reqIdHeaders(requestId) }
      );
    }

    logAmsEdge("company-reports", "info", {
      request_id: requestId,
      company_id: session.company_id,
      user_id: session.user_id,
      report: "daily_attendance",
      outcome: "ok",
      span_days: spanDays,
      duration_ms: durationMs
    });

    const warnExtra =
      spanDays > WARN_DAILY_SPAN_DAYS
        ? { "X-AMS-Report-Warning": "large_date_range" }
        : undefined;
    return jsonResponse(
      {
        ok: true,
        result: data,
        meta: {
          range: { from: fmtUtc(fromD), to: fmtUtc(toD) },
          span_days: spanDays,
          ...(spanDays > WARN_DAILY_SPAN_DAYS ? { warning: "large_date_range" } : {})
        }
      },
      { headers: reqIdHeaders(requestId, warnExtra) }
    );
  }

  const t0 = performance.now();
  let prodRes: { data: unknown; error: { message: string } | null };
  let statRes: { data: unknown; error: { message: string } | null };
  try {
    [prodRes, statRes] = await Promise.all([
      svc.client
        .from("ams_vw_company_productivity_report")
        .select("ams_company_id,day,staff_punched_any")
        .eq("ams_company_id", session.company_id)
        .gte("day", fromIso)
        .lte("day", toIso)
        .order("day", { ascending: true }),
      svc.client
        .from("ams_vw_station_attendance_summary")
        .select("ams_company_id,ams_station_id,punch_day,punch_in_count,punch_out_count")
        .eq("ams_company_id", session.company_id)
        .gte("punch_day", fromIso)
        .lte("punch_day", toIso)
        .order("punch_day", { ascending: true })
    ]);
  } catch (e) {
    const durationMs = Math.round(performance.now() - t0);
    const err = e instanceof Error ? e.message : String(e);
    logAmsEdge("company-reports", "error", {
      request_id: requestId,
      company_id: session.company_id,
      user_id: session.user_id,
      report: "summary",
      outcome: "query_exception",
      span_days: spanDays,
      duration_ms: durationMs,
      message: err
    });
    return jsonResponse(
      { error: "db_error", code: "query_failed", request_id: requestId },
      { status: 500, headers: reqIdHeaders(requestId) }
    );
  }

  if (prodRes.error) {
    logAmsEdge("company-reports", "error", {
      request_id: requestId,
      company_id: session.company_id,
      user_id: session.user_id,
      report: "summary",
      outcome: "productivity_view_error",
      span_days: spanDays,
      message: prodRes.error.message
    });
    return jsonResponse(
      { error: "db_error", details: prodRes.error.message, request_id: requestId },
      { status: 500, headers: reqIdHeaders(requestId) }
    );
  }
  if (statRes.error) {
    logAmsEdge("company-reports", "error", {
      request_id: requestId,
      company_id: session.company_id,
      user_id: session.user_id,
      report: "summary",
      outcome: "station_summary_view_error",
      span_days: spanDays,
      message: statRes.error.message
    });
    return jsonResponse(
      { error: "db_error", details: statRes.error.message, request_id: requestId },
      { status: 500, headers: reqIdHeaders(requestId) }
    );
  }

  const durationMs = Math.round(performance.now() - t0);
  logAmsEdge("company-reports", "info", {
    request_id: requestId,
    company_id: session.company_id,
    user_id: session.user_id,
    report: "summary",
    outcome: "ok",
    span_days: spanDays,
    duration_ms: durationMs
  });

  const stationIds = [...new Set((statRes.data ?? []).map((r: { ams_station_id: string | null }) => r.ams_station_id).filter(Boolean))] as string[];

  const stationsMap: Record<string, { code: string; name: string }> = {};
  if (stationIds.length > 0) {
    const { data: stations } = await svc.client
      .from("ams_station")
      .select("id,code,name")
      .eq("ams_company_id", session.company_id)
      .in("id", stationIds);
    for (const s of stations ?? []) {
      const row = s as { id: string; code: string; name: string };
      stationsMap[row.id] = { code: row.code, name: row.name };
    }
  }

  const warnExtra =
    spanDays > WARN_DAILY_SPAN_DAYS ? { "X-AMS-Report-Warning": "large_date_range" } : undefined;

  return jsonResponse(
    {
      ok: true,
      result: {
        range: { from: fmtUtc(fromD), to: fmtUtc(toD) },
        productivity: prodRes.data ?? [],
        stationAttendance: (statRes.data ?? []).map((r: Record<string, unknown>) => ({
          ...r,
          station: r.ams_station_id ? stationsMap[String(r.ams_station_id)] ?? null : null
        }))
      },
      meta: {
        span_days: spanDays,
        ...(spanDays > WARN_DAILY_SPAN_DAYS ? { warning: "large_date_range" } : {})
      }
    },
    { headers: reqIdHeaders(requestId, warnExtra) }
  );
});
