import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";
import { logAmsEdge } from "./ams_log.ts";

export type AmsServiceClient = ReturnType<typeof createClient>;

export async function listCompanyUserIdsWithPermission(
  client: AmsServiceClient,
  companyId: string,
  permissionCode: string
): Promise<string[]> {
  const { data: perm, error: permErr } = await client
    .from("ams_permission")
    .select("id")
    .eq("code", permissionCode)
    .eq("is_active", true)
    .maybeSingle();

  if (permErr || !perm?.id) {
    logAmsEdge("ams_notifications", "warn", {
      event: "listCompanyUserIdsWithPermission_perm_lookup_failed",
      companyId,
      permissionCode,
      details: permErr?.message ?? "permission_not_found"
    });
    return [];
  }

  const permissionId = String(perm.id);

  const { data: maps, error: mapErr } = await client
    .from("ams_role_permission_map")
    .select("ams_role_id")
    .eq("ams_permission_id", permissionId);

  if (mapErr) {
    logAmsEdge("ams_notifications", "warn", {
      event: "listCompanyUserIdsWithPermission_map_failed",
      companyId,
      permissionCode,
      details: mapErr.message
    });
    return [];
  }

  const roleIds = [...new Set((maps ?? []).map((m: any) => String(m?.ams_role_id ?? "")).filter(Boolean))];
  if (roleIds.length === 0) return [];

  const { data: roles, error: rolesErr } = await client
    .from("ams_role")
    .select("id, is_active, is_platform_role, ams_company_id")
    .in("id", roleIds)
    .eq("is_active", true);

  if (rolesErr) {
    logAmsEdge("ams_notifications", "warn", {
      event: "listCompanyUserIdsWithPermission_roles_failed",
      companyId,
      permissionCode,
      details: rolesErr.message
    });
    return [];
  }

  const eligibleRoleIds = new Set<string>();
  for (const r of roles ?? []) {
    const rid = String((r as any)?.id ?? "");
    if (!rid) continue;
    const isPlatformRole = Boolean((r as any)?.is_platform_role);
    const roleCompanyId = (r as any)?.ams_company_id == null ? null : String((r as any).ams_company_id);
    if (isPlatformRole || roleCompanyId === companyId) eligibleRoleIds.add(rid);
  }
  if (eligibleRoleIds.size === 0) return [];

  const { data: urms, error: urmErr } = await client
    .from("ams_user_role_map")
    .select("ams_user_id, ams_company_id, ams_role_id")
    .eq("is_active", true)
    .in("ams_role_id", [...eligibleRoleIds]);

  if (urmErr) {
    logAmsEdge("ams_notifications", "warn", {
      event: "listCompanyUserIdsWithPermission_urms_failed",
      companyId,
      permissionCode,
      details: urmErr.message
    });
    return [];
  }

  const out = new Set<string>();
  for (const row of urms ?? []) {
    const userId = String((row as any)?.ams_user_id ?? "").trim();
    if (!userId) continue;
    const urmCompanyId = (row as any)?.ams_company_id == null ? null : String((row as any).ams_company_id);
    if (urmCompanyId != null && urmCompanyId !== companyId) continue;
    out.add(userId);
  }

  return [...out];
}

export async function enqueuePushNotification(args: {
  client: AmsServiceClient;
  companyId: string;
  userId: string;
  notifType: string;
  title: string;
  body?: string | null;
  payload?: Record<string, unknown>;
  createdBy?: string | null;
  priority?: "low" | "normal" | "high";
}): Promise<boolean> {
  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  const trimmedTitle = String(args.title ?? "").trim() || "Notification";
  const trimmedBodyRaw = args.body == null ? "" : String(args.body).trim();
  const trimmedBody = trimmedBodyRaw.length > 0 ? trimmedBodyRaw : " ";

  const payload_json = {
    ...(args.payload ?? {}),
    notifType: args.notifType
  };

  const row: Record<string, unknown> = {
    id,
    ams_company_id: args.companyId,
    ams_user_id: args.userId,
    notif_type: args.notifType,
    title: trimmedTitle,
    body: trimmedBody,
    payload_json,
    status: "queued",
    channel: "push",
    priority: args.priority ?? "normal",
    created_at: now,
    updated_at: now,
    created_by: args.createdBy ?? null,
    updated_by: args.createdBy ?? null,
    // Legacy columns from early AMS_notification (004) — harmless if absent.
    target_type: "user",
    target_id: args.userId
  };

  const { error } = await args.client.from("ams_notification").insert(row);
  if (error) {
    logAmsEdge("ams_notifications", "warn", {
      event: "enqueuePushNotification_failed",
      companyId: args.companyId,
      userId: args.userId,
      notifType: args.notifType,
      details: error.message
    });
    return false;
  }

  return true;
}
