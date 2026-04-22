import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, jsonResponse, optionsResponse } from "../_shared/http.ts";
import { enqueuePushNotification, listCompanyUserIdsWithPermission } from "../_shared/ams_notifications.ts";

const STATUSES = ["open", "in_progress", "resolved", "closed", "cancelled"] as const;
const PRIORITIES = ["low", "medium", "high", "critical"] as const;

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

  async function getCompanyPermissionCodes(): Promise<string[]> {
    const { data: perms } = await svc.client.rpc("ams_fn_get_user_permission_codes", {
      p_user_id: session.user_id,
      p_company_id: session.company_id
    });
    return (perms ?? []).map((r: { permission_code: string }) => r.permission_code);
  }

  async function requirePerm(code: string) {
    if (user.is_platform_super_admin) return;
    const codes = await getCompanyPermissionCodes();
    if (!codes.includes(code)) throw new Error("forbidden");
  }

  const url = new URL(req.url);
  const action = (url.searchParams.get("action") ?? "").trim();

  try {
    if (req.method === "GET") {
      const codes = user.is_platform_super_admin ? null : await getCompanyPermissionCodes();
      const canReadAll = user.is_platform_super_admin || (codes?.includes("COMPANY_SUPPORT_READ") ?? false);
      const canReadOwn = codes?.includes("STAFF_SUPPORT_TICKET") ?? false;
      if (!canReadAll && !canReadOwn) {
        return jsonResponse({ error: "forbidden" }, { status: 403 });
      }

      const page = Math.max(1, Number(url.searchParams.get("page") ?? "1"));
      const pageSize = Math.min(100, Math.max(1, Number(url.searchParams.get("pageSize") ?? "25")));
      const statusFilter = (url.searchParams.get("status") ?? "").trim();
      const fromDate = (url.searchParams.get("from") ?? "").trim();
      const toDate = (url.searchParams.get("to") ?? "").trim();

      const isoDate = (s: string) => /^\d{4}-\d{2}-\d{2}$/.test(s);
      if (fromDate && !isoDate(fromDate)) {
        return jsonResponse({ error: "invalid_query", details: "from_must_be_YMD" }, { status: 400 });
      }
      if (toDate && !isoDate(toDate)) {
        return jsonResponse({ error: "invalid_query", details: "to_must_be_YMD" }, { status: 400 });
      }
      if (fromDate && toDate && fromDate > toDate) {
        return jsonResponse({ error: "invalid_query", details: "from_after_to" }, { status: 400 });
      }

      const rangeFrom = (page - 1) * pageSize;
      const rangeTo = rangeFrom + pageSize - 1;

      let query = svc.client
        .from("ams_support_ticket")
        .select(
          "id,ticket_code,title,description,priority,status,opened_at,due_by,closed_at,opened_by",
          { count: "exact" }
        )
        .eq("ams_company_id", session.company_id)
        .order("opened_at", { ascending: false });

      if (!canReadAll && canReadOwn) {
        query = query.eq("opened_by", session.user_id);
      }

      if (statusFilter && (STATUSES as readonly string[]).includes(statusFilter)) {
        query = query.eq("status", statusFilter);
      }

      if (fromDate) {
        query = query.gte("opened_at", `${fromDate}T00:00:00.000Z`);
      }
      if (toDate) {
        query = query.lte("opened_at", `${toDate}T23:59:59.999Z`);
      }

      const { data, error, count } = await query.range(rangeFrom, rangeTo);
      if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });

      return jsonResponse({ ok: true, result: { items: data ?? [], page, pageSize, total: count ?? 0 } });
    }

    if (req.method === "POST" && action === "create") {
      const codes = user.is_platform_super_admin ? null : await getCompanyPermissionCodes();
      const canCreate =
        user.is_platform_super_admin ||
        (codes?.includes("COMPANY_SUPPORT_WRITE") ?? false) ||
        (codes?.includes("STAFF_SUPPORT_TICKET") ?? false);
      if (!canCreate) {
        return jsonResponse({ error: "forbidden" }, { status: 403 });
      }
      const body = await req.json().catch(() => null);
      const title = String(body?.title ?? "").trim();
      if (!title) return jsonResponse({ error: "invalid_body", details: "title_required" }, { status: 400 });

      const pr = String(body?.priority ?? "");
      const priority = (PRIORITIES as readonly string[]).includes(pr) ? pr : "medium";
      const id = crypto.randomUUID();
      const ticket_code = `TKT-${crypto.randomUUID().replace(/-/g, "").slice(0, 12).toUpperCase()}`;

      const { data, error } = await svc.client
        .from("ams_support_ticket")
        .insert({
          id,
          ams_company_id: session.company_id,
          ticket_code,
          title,
          description: body?.description != null ? String(body.description) : null,
          priority,
          opened_by: session.user_id,
          status: "open"
        })
        .select("id,ticket_code,title,status,priority,opened_at")
        .single();

      if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });

      const companyId = session.company_id as string;
      const readIds = await listCompanyUserIdsWithPermission(svc.client, companyId, "COMPANY_SUPPORT_READ");
      const writeIds = await listCompanyUserIdsWithPermission(svc.client, companyId, "COMPANY_SUPPORT_WRITE");
      const notify = new Set<string>([...readIds, ...writeIds]);
      notify.delete(session.user_id);

      // Option A: only notify mobile staff users (active user↔staff mapping).
      const { data: staffMaps } = await svc.client
        .from("ams_user_staff_map")
        .select("ams_user_id")
        .eq("ams_company_id", companyId)
        .eq("is_active", true);
      const staffUserIds = new Set<string>(
        (staffMaps ?? []).map((m: any) => String(m?.ams_user_id ?? "")).filter(Boolean),
      );

      for (const uid of notify) {
        if (!staffUserIds.has(uid)) continue;
        await enqueuePushNotification({
          client: svc.client,
          companyId,
          userId: uid,
          notifType: "support_ticket_created",
          title: `New support ticket ${data.ticket_code}`,
          body: data.title,
          createdBy: session.user_id,
          payload: { ticketId: data.id, ticketCode: data.ticket_code }
        });
      }

      return jsonResponse({ ok: true, result: data });
    }

    if (req.method === "POST" && action === "set-status") {
      await requirePerm("COMPANY_SUPPORT_WRITE");
      const body = await req.json().catch(() => null);
      const id = String(body?.id ?? "").trim();
      const status = String(body?.status ?? "").trim();
      if (!id || !(STATUSES as readonly string[]).includes(status)) {
        return jsonResponse({ error: "invalid_body" }, { status: 400 });
      }

      const patch: Record<string, unknown> = { status, updated_at: new Date().toISOString() };
      if (status === "closed" || status === "resolved") patch.closed_at = new Date().toISOString();
      else patch.closed_at = null;

      const { data, error } = await svc.client
        .from("ams_support_ticket")
        .update(patch)
        .eq("id", id)
        .eq("ams_company_id", session.company_id)
        .select("id,ticket_code,title,status,closed_at,opened_by")
        .maybeSingle();

      if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });
      if (!data) return jsonResponse({ error: "not_found" }, { status: 404 });

      const openedBy = data.opened_by == null ? null : String(data.opened_by);
      if (openedBy && openedBy !== session.user_id) {
        const companyId = session.company_id as string;
        await enqueuePushNotification({
          client: svc.client,
          companyId,
          userId: openedBy,
          notifType: "support_ticket_updated",
          title: `Ticket ${data.ticket_code} is now ${data.status}`,
          body: data.title,
          createdBy: session.user_id,
          payload: { ticketId: data.id, ticketCode: data.ticket_code, status: data.status }
        });
      }

      return jsonResponse({ ok: true, result: data });
    }
  } catch (e) {
    if (String(e?.message ?? e) === "forbidden") return jsonResponse({ error: "forbidden" }, { status: 403 });
    throw e;
  }

  return jsonResponse({ error: "method_not_allowed" }, { status: 405 });
});
