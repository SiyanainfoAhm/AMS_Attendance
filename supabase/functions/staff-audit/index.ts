import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, jsonResponse, optionsResponse } from "../_shared/http.ts";
import { enqueuePushNotification, listCompanyUserIdsWithPermission } from "../_shared/ams_notifications.ts";

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

  if (req.method === "GET") {
    const status = (url.searchParams.get("status") ?? "open").trim();
    const limit = Math.min(200, Math.max(1, Number(url.searchParams.get("limit") ?? "50")));

    const { data, error } = await svc.client.rpc("ams_sp_staff_audit_list", {
      p_access_token: accessToken,
      p_status: status,
      p_limit: limit
    });
    if (error) {
      const msg = error.message ?? "";
      if (msg.includes("staff_user_mapping_required")) return jsonResponse({ error: "staff_user_mapping_required" }, { status: 400 });
      return jsonResponse({ error: "audit_list_failed", details: msg }, { status: 400 });
    }
    return jsonResponse({ ok: true, result: data });
  }

  if (req.method === "POST") {
    const body = await req.json().catch(() => null);
    const { data, error } = await svc.client.rpc("ams_sp_staff_audit_submit_response", {
      p_access_token: accessToken,
      p_case_id: body?.caseId ?? null,
      p_response_text: body?.responseText ?? null
    });
    if (error) {
      const msg = error.message ?? "";
      if (msg.includes("staff_user_mapping_required")) return jsonResponse({ error: "staff_user_mapping_required" }, { status: 400 });
      if (msg.includes("case_id_required")) return jsonResponse({ error: "case_id_required" }, { status: 400 });
      if (msg.includes("response_required")) return jsonResponse({ error: "response_required" }, { status: 400 });
      if (msg.includes("case_not_found")) return jsonResponse({ error: "case_not_found" }, { status: 404 });
      if (msg.includes("case_not_open")) return jsonResponse({ error: "case_not_open" }, { status: 400 });
      return jsonResponse({ error: "audit_submit_failed", details: msg }, { status: 400 });
    }

    const caseId = String(body?.caseId ?? "").trim();
    if (caseId) {
      const companyId = session.company_id as string;
      const readIds = await listCompanyUserIdsWithPermission(svc.client, companyId, "COMPANY_ATTENDANCE_READ");
      const writeIds = await listCompanyUserIdsWithPermission(svc.client, companyId, "COMPANY_ATTENDANCE_WRITE");
      const notify = new Set<string>([...readIds, ...writeIds]);
      notify.delete(session.user_id);

      const { data: c } = await svc.client
        .from("ams_audit_case")
        .select("id,title,shift_date,case_type,status")
        .eq("id", caseId)
        .eq("ams_company_id", companyId)
        .maybeSingle();

      const titleText = c?.title != null ? String(c.title) : "Attendance audit case";
      const when = c?.shift_date != null ? String(c.shift_date) : "";

      for (const uid of notify) {
        await enqueuePushNotification({
          client: svc.client,
          companyId,
          userId: uid,
          notifType: "audit_case_response",
          title: `Staff replied to an audit case`,
          body: when ? `${titleText} (${when})` : titleText,
          createdBy: session.user_id,
          payload: {
            caseId,
            shiftDate: c?.shift_date ?? null,
            caseType: c?.case_type ?? null,
            status: c?.status ?? null
          }
        });
      }
    }

    return jsonResponse({ ok: true, result: data });
  }

  return jsonResponse({ error: "method_not_allowed" }, { status: 405 });
});

