import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getBearerToken, jsonResponse, optionsResponse } from "../_shared/http.ts";
import { enqueuePushNotification } from "../_shared/ams_notifications.ts";

type Body = {
  companyId?: string;
  from?: string; // YYYY-MM-DD
  to?: string; // YYYY-MM-DD
  staffId?: string;
  limit?: number;
  dryRun?: boolean;
};

function isIsoDate(s: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(s);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse();
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, { status: 405 });

  const svc = tryGetServiceClient();
  if (!svc.ok) return jsonResponse({ error: "server_misconfigured", details: svc.error }, { status: 500 });

  // Cron-friendly auth: require either dispatch secret header OR service-role bearer.
  const dispatchSecret = (Deno.env.get("NOTIFICATIONS_DISPATCH_SECRET") ?? "").trim();
  const hdrSecret =
    (req.headers.get("x-ams-dispatch-secret") ?? req.headers.get("x-notifications-dispatch-secret") ?? "").trim();
  const bearer = (getBearerToken(req) ?? "").trim();
  const serviceRole = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();

  const isTrusted =
    (dispatchSecret.length > 0 && hdrSecret.length > 0 && hdrSecret === dispatchSecret) ||
    (serviceRole.length > 0 && bearer.length > 0 && bearer === serviceRole);

  if (!isTrusted) return jsonResponse({ error: "unauthorized" }, { status: 401 });

  const body = (await req.json().catch(() => null)) as Body | null;
  const dryRun = Boolean(body?.dryRun);
  const limit = Math.min(500, Math.max(1, Number(body?.limit ?? 200)));

  const from = String(body?.from ?? "").trim();
  const to = String(body?.to ?? "").trim();
  const companyId = String(body?.companyId ?? "").trim();
  const staffId = String(body?.staffId ?? "").trim();

  if (!companyId) return jsonResponse({ error: "invalid_body", details: "companyId_required" }, { status: 400 });
  if (!from || !to) return jsonResponse({ error: "invalid_body", details: "from_to_required" }, { status: 400 });
  if (!isIsoDate(from) || !isIsoDate(to)) {
    return jsonResponse({ error: "invalid_body", details: "from_to_must_be_YMD" }, { status: 400 });
  }
  if (from > to) return jsonResponse({ error: "invalid_body", details: "from_after_to" }, { status: 400 });

  // Generate (and RETURN) newly inserted audit cases.
  const { data: inserted, error: genErr } = await svc.client.rpc(
    "ams_fn_audit_generate_missing_attendance_from_rollup_returning",
    {
      p_company_id: companyId,
      p_from: from,
      p_to: to,
      p_staff_id: staffId || null,
    },
  );

  if (genErr) {
    return jsonResponse({ error: "generate_failed", details: genErr.message }, { status: 400 });
  }

  const rows = ((inserted ?? []) as any[]).slice(0, limit);
  if (rows.length === 0) return jsonResponse({ ok: true, result: { generated: 0, notified: 0, dryRun } });

  let notified = 0;
  for (const r of rows) {
    const caseId = String(r?.audit_case_id ?? "").trim();
    const staff = String(r?.staff_id ?? "").trim();
    if (!caseId || !staff) continue;

    const { data: maps } = await svc.client
      .from("ams_user_staff_map")
      .select("ams_user_id")
      .eq("ams_company_id", companyId)
      .eq("ams_staff_id", staff)
      .eq("is_active", true);

    const userIds = [...new Set((maps ?? []).map((m: any) => String(m?.ams_user_id ?? "")).filter(Boolean))];
    for (const uid of userIds) {
      if (dryRun) {
        notified++;
        continue;
      }
      const ok = await enqueuePushNotification({
        client: svc.client,
        companyId,
        userId: uid,
        notifType: "audit_case_created",
        title: "Attendance action required",
        body: String(r?.title ?? "Please review your attendance audit case."),
        createdBy: null,
        payload: {
          caseId,
          caseType: r?.case_kind ?? null,
          shiftDate: r?.shift_day ?? null,
        },
        priority: "high",
      });
      if (ok) notified++;
    }
  }

  return jsonResponse({ ok: true, result: { generated: rows.length, notified, dryRun } });
});

