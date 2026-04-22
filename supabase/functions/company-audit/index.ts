import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, jsonResponse, optionsResponse } from "../_shared/http.ts";
import { enqueuePushNotification } from "../_shared/ams_notifications.ts";

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

  // Basic RBAC: list requires read, set-status requires write.
  // Platform super admin bypasses.
  async function hasPerm(code: string): Promise<boolean> {
    if (user.is_platform_super_admin) return true;
    const { data: perms } = await svc.client.rpc("ams_fn_get_user_permission_codes", {
      p_user_id: session.user_id,
      p_company_id: session.company_id
    });
    const codes = (perms ?? []).map((r: { permission_code: string }) => r.permission_code);
    return codes.includes(code);
  }

  const url = new URL(req.url);
  const action = (url.searchParams.get("action") ?? "").trim();

  if (req.method === "GET") {
    if (!(await hasPerm("COMPANY_ATTENDANCE_READ"))) return jsonResponse({ error: "forbidden" }, { status: 403 });

    const status = (url.searchParams.get("status") ?? "open").trim();
    const caseType = (url.searchParams.get("caseType") ?? "").trim() || null;
    const from = (url.searchParams.get("from") ?? "").trim() || null;
    const to = (url.searchParams.get("to") ?? "").trim() || null;
    const staffId = (url.searchParams.get("staffId") ?? "").trim() || null;
    const stationId = (url.searchParams.get("stationId") ?? "").trim() || null;
    const limit = Math.min(500, Math.max(1, Number(url.searchParams.get("limit") ?? "200")));

    const { data, error } = await svc.client.rpc("ams_sp_company_audit_list", {
      p_access_token: accessToken,
      p_status: status,
      p_case_type: caseType,
      p_from: from,
      p_to: to,
      p_staff_id: staffId,
      p_station_id: stationId,
      p_limit: limit
    });
    if (error) {
      const msg = error.message ?? "";
      if (msg.includes("forbidden")) return jsonResponse({ error: "forbidden" }, { status: 403 });
      return jsonResponse({ error: "audit_list_failed", details: msg }, { status: 400 });
    }
    return jsonResponse({ ok: true, result: data });
  }

  if (req.method === "POST" && action === "set-status") {
    if (!(await hasPerm("COMPANY_ATTENDANCE_WRITE"))) return jsonResponse({ error: "forbidden" }, { status: 403 });

    const body = await req.json().catch(() => null);
    const { data, error } = await svc.client.rpc("ams_sp_company_audit_set_status", {
      p_access_token: accessToken,
      p_case_id: body?.caseId ?? null,
      p_status: body?.status ?? null
    });
    if (error) {
      const msg = error.message ?? "";
      if (msg.includes("forbidden")) return jsonResponse({ error: "forbidden" }, { status: 403 });
      if (msg.includes("case_id_required")) return jsonResponse({ error: "case_id_required" }, { status: 400 });
      if (msg.includes("invalid_status")) return jsonResponse({ error: "invalid_status" }, { status: 400 });
      if (msg.includes("case_not_found")) return jsonResponse({ error: "case_not_found" }, { status: 404 });
      return jsonResponse({ error: "audit_set_status_failed", details: msg }, { status: 400 });
    }

    const nextStatus = String(body?.status ?? "").trim();
    const caseId = String(body?.caseId ?? "").trim();
    if (caseId && (nextStatus === "resolved" || nextStatus === "dismissed")) {
      const companyId = session.company_id as string;

      const { data: c } = await svc.client
        .from("ams_audit_case")
        .select("id,ams_staff_id,title,shift_date,case_type,status")
        .eq("id", caseId)
        .eq("ams_company_id", companyId)
        .maybeSingle();

      if (c?.ams_staff_id) {
        const staffId = String(c.ams_staff_id);
        const { data: maps } = await svc.client
          .from("ams_user_staff_map")
          .select("ams_user_id")
          .eq("ams_company_id", companyId)
          .eq("ams_staff_id", staffId)
          .eq("is_active", true);

        const userIds = [...new Set((maps ?? []).map((m: any) => String(m?.ams_user_id ?? "")).filter(Boolean))];
        const titleText = String(c.title ?? "Attendance audit case");
        const when = String(c.shift_date ?? "");

        for (const uid of userIds) {
          await enqueuePushNotification({
            client: svc.client,
            companyId,
            userId: uid,
            notifType: "audit_case_updated",
            title: nextStatus === "resolved" ? `Audit case resolved` : `Audit case dismissed`,
            body: when ? `${titleText} (${when})` : titleText,
            createdBy: session.user_id,
            payload: {
              caseId: c.id,
              caseType: c.case_type,
              shiftDate: c.shift_date,
              status: nextStatus
            }
          });
        }
      }
    }

    return jsonResponse({ ok: true, result: data });
  }

  return jsonResponse({ error: "method_not_allowed" }, { status: 405 });
});

