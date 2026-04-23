import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, jsonResponse, optionsResponse } from "../_shared/http.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse();
  if (req.method !== "GET") return jsonResponse({ error: "method_not_allowed" }, { status: 405 });

  const accessToken = getAmsAccessToken(req);
  if (!accessToken) return jsonResponse({ error: "missing_access_token" }, { status: 401 });

  const svc = tryGetServiceClient();
  if (!svc.ok) return jsonResponse({ error: "server_misconfigured", details: svc.error }, { status: 500 });

  const { data: sess, error: sessErr } = await svc.client.rpc("ams_fn_validate_user_session", {
    p_access_token: accessToken
  });

  if (sessErr || !Array.isArray(sess) || sess.length === 0) {
    return jsonResponse({ error: "invalid_session" }, { status: 401 });
  }

  const session = sess[0] as {
    user_id: string;
    company_id: string | null;
    session_id: string;
  };

  const { data: user, error: userErr } = await svc.client
    .from("ams_user")
    .select("id, display_name, email, is_platform_super_admin, is_active")
    .eq("id", session.user_id)
    .maybeSingle();

  if (userErr || !user) return jsonResponse({ error: "user_not_found" }, { status: 404 });

  const { data: companies } = await svc.client.rpc("ams_fn_get_user_companies", {
    p_user_id: session.user_id
  });

  const companyId = session.company_id;
  const selectedCompany =
    companyId && Array.isArray(companies)
      ? (companies as any[]).find((c) => String(c?.company_id ?? c?.id ?? "") === String(companyId)) ?? null
      : null;
  const rbac =
    companyId && typeof companyId === "string"
      ? await Promise.all([
          svc.client.rpc("ams_fn_get_user_roles", { p_user_id: session.user_id, p_company_id: companyId }),
          svc.client.rpc("ams_fn_get_user_permission_codes", {
            p_user_id: session.user_id,
            p_company_id: companyId
          })
        ])
      : null;

  const roles = rbac ? (rbac[0].data ?? []) : [];
  const permissions = rbac ? (rbac[1].data?.map((r: any) => r.permission_code) ?? []) : [];

  let mappedStaffId: string | null = null;
  let mappedStaff: any | null = null;
  if (companyId && typeof companyId === "string") {
    const { data: mapRow } = await svc.client
      .from("ams_user_staff_map")
      .select("ams_staff_id")
      .eq("ams_user_id", session.user_id)
      .eq("ams_company_id", companyId)
      .eq("is_active", true)
      .maybeSingle();
    mappedStaffId = (mapRow as { ams_staff_id?: string } | null)?.ams_staff_id ?? null;

    if (mappedStaffId) {
      const { data: staffRow } = await svc.client
        .from("ams_staff")
        .select("id, staff_code, full_name, is_active")
        .eq("id", mappedStaffId)
        .eq("ams_company_id", companyId)
        .maybeSingle();
      if (staffRow) {
        mappedStaff = {
          id: staffRow.id,
          staffCode: (staffRow as any).staff_code ?? null,
          fullName: (staffRow as any).full_name ?? null,
          isActive: (staffRow as any).is_active ?? null
        };
      }
    }
  }

  return jsonResponse({
    ok: true,
    result: {
      user,
      session,
      companies: companies ?? [],
      selectedCompany: selectedCompany
        ? {
            id: String((selectedCompany as any).company_id ?? (selectedCompany as any).id ?? ""),
            code: (selectedCompany as any).company_code ?? (selectedCompany as any).code ?? null,
            name: (selectedCompany as any).company_name ?? (selectedCompany as any).name ?? null
          }
        : null,
      roles,
      permissions,
      mappedStaffId,
      mappedStaff
    }
  });
});

