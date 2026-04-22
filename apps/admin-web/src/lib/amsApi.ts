import { getAmsFunctionsBaseUrl } from "./config";
import { getSupabaseAnonKey } from "./config";

export const AMS_SESSION_INVALID_EVENT = "ams:session-invalid";

export type AmsTokens = {
  accessToken: string;
  refreshToken: string;
};

function getSupabaseGatewayHeaders(): Record<string, string> {
  const anon = getSupabaseAnonKey();
  return {
    apikey: anon,
    authorization: `Bearer ${anon}`
  };
}

async function readJson(res: Response): Promise<any> {
  try {
    return await res.json();
  } catch {
    return null;
  }
}

function emitSessionInvalid() {
  window.dispatchEvent(new Event(AMS_SESSION_INVALID_EVENT));
}

function handleAmsJsonResponse(res: Response, json: any) {
  if (res.status === 401 && json?.error === "invalid_session") emitSessionInvalid();
  if (!res.ok) {
    const base = json?.details ?? json?.error ?? "request_failed";
    const ref = json?.request_id;
    throw new Error(ref ? `${base} (ref: ${ref})` : base);
  }
}

export async function amsLogin(email: string, password: string) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/auth-login`, {
    method: "POST",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "content-type": "application/json"
    },
    body: JSON.stringify({ email, password, clientType: "web" })
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function amsSelectCompany(accessToken: string, companyId: string) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/select-company`, {
    method: "POST",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "content-type": "application/json",
      "x-ams-access-token": accessToken
    },
    body: JSON.stringify({ companyId })
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function amsMe(accessToken: string) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/me`, {
    method: "GET",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "x-ams-access-token": accessToken
    }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function amsRefresh(refreshToken: string) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/auth-refresh`, {
    method: "POST",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "content-type": "application/json",
      "x-ams-refresh-token": refreshToken
    }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function amsLogout(accessToken: string) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/auth-logout`, {
    method: "POST",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "x-ams-access-token": accessToken
    }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

/** Always succeeds with { requested: true } if email format ok; optional reset_token in dev. */
export async function amsRequestPasswordReset(email: string) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/auth-password-reset-request`, {
    method: "POST",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "content-type": "application/json"
    },
    body: JSON.stringify({ email })
  });
  const json = await readJson(res);
  if (!res.ok) throw new Error(json?.details ?? json?.error ?? "request_failed");
  return json.result as { requested: boolean; reset_token?: string };
}

export async function amsConfirmPasswordReset(resetToken: string, newPassword: string) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/auth-password-reset-confirm`, {
    method: "POST",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "content-type": "application/json"
    },
    body: JSON.stringify({ resetToken, newPassword })
  });
  const json = await readJson(res);
  if (!res.ok) throw new Error(json?.details ?? json?.error ?? "reset_failed");
  return json.result as { reset: boolean };
}

export async function platformCompaniesList(accessToken: string, params: { page: number; pageSize: number; q?: string }) {
  const sp = new URLSearchParams();
  sp.set("page", String(params.page));
  sp.set("pageSize", String(params.pageSize));
  if (params.q) sp.set("q", params.q);

  const res = await fetch(`${getAmsFunctionsBaseUrl()}/platform-companies?${sp.toString()}`, {
    method: "GET",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "x-ams-access-token": accessToken
    }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function platformCompanyCreate(
  accessToken: string,
  input: { code: string; name: string; timezone?: string }
) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/platform-companies`, {
    method: "POST",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "content-type": "application/json",
      "x-ams-access-token": accessToken
    },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function platformCompanyUpdate(
  accessToken: string,
  input: { companyId: string; name?: string; isActive?: boolean }
) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/platform-companies`, {
    method: "PATCH",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "content-type": "application/json",
      "x-ams-access-token": accessToken
    },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function platformUsersList(
  accessToken: string,
  params: { page: number; pageSize: number; q?: string; includeMeta?: boolean }
) {
  const sp = new URLSearchParams();
  sp.set("page", String(params.page));
  sp.set("pageSize", String(params.pageSize));
  if (params.q) sp.set("q", params.q);
  if (params.includeMeta) sp.set("include", "meta");

  const res = await fetch(`${getAmsFunctionsBaseUrl()}/platform-users?${sp.toString()}`, {
    method: "GET",
    headers: { ...getSupabaseGatewayHeaders(), "x-ams-access-token": accessToken }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function platformUserCreate(
  accessToken: string,
  input: { displayName: string; email: string; password: string; isPlatformSuperAdmin?: boolean }
) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/platform-users?action=create`, {
    method: "POST",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "content-type": "application/json",
      "x-ams-access-token": accessToken
    },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function platformUserUpdate(
  accessToken: string,
  input: { userId: string; displayName?: string; email?: string; password?: string; isPlatformSuperAdmin?: boolean; isActive?: boolean }
) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/platform-users?action=update`, {
    method: "POST",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "content-type": "application/json",
      "x-ams-access-token": accessToken
    },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function platformUserSetActive(accessToken: string, input: { userId: string; isActive: boolean }) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/platform-users?action=set-active`, {
    method: "POST",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "content-type": "application/json",
      "x-ams-access-token": accessToken
    },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function platformUserMapCompany(
  accessToken: string,
  input: { userId: string; companyId: string; isActive?: boolean }
) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/platform-users?action=map-company`, {
    method: "POST",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "content-type": "application/json",
      "x-ams-access-token": accessToken
    },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function platformUserCompanyMapsList(accessToken: string, userId: string) {
  const sp = new URLSearchParams();
  sp.set("action", "list-company-maps");
  sp.set("userId", userId);
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/platform-users?${sp.toString()}`, {
    method: "GET",
    headers: { ...getSupabaseGatewayHeaders(), "x-ams-access-token": accessToken }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function platformUserRoleMapsList(accessToken: string, userId: string) {
  const sp = new URLSearchParams();
  sp.set("action", "list-role-maps");
  sp.set("userId", userId);
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/platform-users?${sp.toString()}`, {
    method: "GET",
    headers: { ...getSupabaseGatewayHeaders(), "x-ams-access-token": accessToken }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function platformUserAssignRole(
  accessToken: string,
  input: { userId: string; roleId: string; companyId?: string | null; isActive?: boolean }
) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/platform-users?action=assign-role`, {
    method: "POST",
    headers: {
      ...getSupabaseGatewayHeaders(),
      "content-type": "application/json",
      "x-ams-access-token": accessToken
    },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyOrgList(
  accessToken: string,
  entity: "zones" | "branches" | "stations" | "geofences",
  params: { page: number; pageSize: number; q?: string }
) {
  const sp = new URLSearchParams();
  sp.set("entity", entity);
  sp.set("page", String(params.page));
  sp.set("pageSize", String(params.pageSize));
  if (params.q) sp.set("q", params.q);

  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-org?${sp.toString()}`, {
    method: "GET",
    headers: { ...getSupabaseGatewayHeaders(), "x-ams-access-token": accessToken }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyOrgCreate(
  accessToken: string,
  entity: "zones" | "branches" | "stations" | "geofences",
  input: any
) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-org?entity=${encodeURIComponent(entity)}`, {
    method: "POST",
    headers: { ...getSupabaseGatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyOrgUpdate(
  accessToken: string,
  entity: "zones" | "branches" | "stations" | "geofences",
  input: any
) {
  const res = await fetch(
    `${getAmsFunctionsBaseUrl()}/company-org?entity=${encodeURIComponent(entity)}&action=update`,
    {
    method: "POST",
    headers: { ...getSupabaseGatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken },
    body: JSON.stringify(input)
    }
  );
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyStaffList(
  accessToken: string,
  params: { page: number; pageSize: number; q?: string; includeMeta?: boolean }
) {
  const sp = new URLSearchParams();
  sp.set("page", String(params.page));
  sp.set("pageSize", String(params.pageSize));
  if (params.q) sp.set("q", params.q);
  if (params.includeMeta) sp.set("include", "meta");

  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-staff?${sp.toString()}`, {
    method: "GET",
    headers: { ...getSupabaseGatewayHeaders(), "x-ams-access-token": accessToken }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyStaffCreate(
  accessToken: string,
  input: { staffCode: string; fullName: string; mobile?: string; email?: string }
) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-staff?action=create`, {
    method: "POST",
    headers: { ...getSupabaseGatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyStaffUpdate(accessToken: string, input: any) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-staff?action=update`, {
    method: "POST",
    headers: { ...getSupabaseGatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyStaffMapStation(accessToken: string, input: any) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-staff?action=map-station`, {
    method: "POST",
    headers: { ...getSupabaseGatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyStaffStationMapsList(accessToken: string, staffId: string) {
  const sp = new URLSearchParams();
  sp.set("action", "list-station-maps");
  sp.set("staffId", staffId);
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-staff?${sp.toString()}`, {
    method: "GET",
    headers: { ...getSupabaseGatewayHeaders(), "x-ams-access-token": accessToken }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyStaffUserLinksList(accessToken: string, staffId: string) {
  const sp = new URLSearchParams();
  sp.set("action", "list-user-links");
  sp.set("staffId", staffId);
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-staff?${sp.toString()}`, {
    method: "GET",
    headers: { ...getSupabaseGatewayHeaders(), "x-ams-access-token": accessToken }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyStaffMapUser(
  accessToken: string,
  input: { userId: string; staffId: string; isActive?: boolean }
) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-staff?action=map-user`, {
    method: "POST",
    headers: { ...getSupabaseGatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken },
    body: JSON.stringify({
      userId: input.userId,
      staffId: input.staffId,
      isActive: input.isActive
    })
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyStaffAddDocument(accessToken: string, input: any) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-staff?action=add-document`, {
    method: "POST",
    headers: { ...getSupabaseGatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyAttendanceList(
  accessToken: string,
  params: {
    page: number;
    pageSize: number;
    stationId?: string;
    staffId?: string;
    date?: string;
    includeMeta?: boolean;
  }
) {
  const sp = new URLSearchParams();
  sp.set("page", String(params.page));
  sp.set("pageSize", String(params.pageSize));
  if (params.stationId) sp.set("stationId", params.stationId);
  if (params.staffId) sp.set("staffId", params.staffId);
  if (params.date) sp.set("date", params.date);
  if (params.includeMeta) sp.set("include", "meta");

  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-attendance?${sp.toString()}`, {
    method: "GET",
    headers: { ...getSupabaseGatewayHeaders(), "x-ams-access-token": accessToken }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyAttendancePunch(
  accessToken: string,
  input: {
    staffId: string;
    punchType: "in" | "out" | "break_in" | "break_out";
    stationId?: string;
    punchAt?: string;
    withinGeofence?: boolean;
    faceMatchScore?: number;
    deviceId?: string;
  }
) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-attendance?action=punch`, {
    method: "POST",
    headers: { ...getSupabaseGatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken },
    body: JSON.stringify({
      staffId: input.staffId,
      punchType: input.punchType,
      stationId: input.stationId,
      punchAt: input.punchAt,
      withinGeofence: input.withinGeofence,
      faceMatchScore: input.faceMatchScore,
      deviceId: input.deviceId
    })
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyReportsSummary(accessToken: string, params: { from?: string; to?: string }) {
  const sp = new URLSearchParams();
  if (params.from) sp.set("from", params.from);
  if (params.to) sp.set("to", params.to);
  const q = sp.toString();
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-reports${q ? `?${q}` : ""}`, {
    method: "GET",
    headers: { ...getSupabaseGatewayHeaders(), "x-ams-access-token": accessToken }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyDailyAttendanceReport(
  accessToken: string,
  params: { from: string; to: string; staffId?: string; stationId?: string }
) {
  const sp = new URLSearchParams();
  sp.set("report", "daily_attendance");
  sp.set("from", params.from);
  sp.set("to", params.to);
  if (params.staffId) sp.set("staffId", params.staffId);
  if (params.stationId) sp.set("stationId", params.stationId);

  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-reports?${sp.toString()}`, {
    method: "GET",
    headers: { ...getSupabaseGatewayHeaders(), "x-ams-access-token": accessToken }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companySupportList(
  accessToken: string,
  params: { page: number; pageSize: number; status?: string; from?: string; to?: string }
) {
  const sp = new URLSearchParams();
  sp.set("page", String(params.page));
  sp.set("pageSize", String(params.pageSize));
  if (params.status) sp.set("status", params.status);
  if (params.from) sp.set("from", params.from);
  if (params.to) sp.set("to", params.to);
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-support?${sp.toString()}`, {
    method: "GET",
    headers: { ...getSupabaseGatewayHeaders(), "x-ams-access-token": accessToken }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companySupportCreate(
  accessToken: string,
  input: { title: string; description?: string; priority?: string }
) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-support?action=create`, {
    method: "POST",
    headers: { ...getSupabaseGatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companySupportSetStatus(accessToken: string, input: { id: string; status: string }) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-support?action=set-status`, {
    method: "POST",
    headers: { ...getSupabaseGatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyAuditList(
  accessToken: string,
  params: {
    status?: "open" | "resolved" | "dismissed";
    caseType?: "missing_out" | "missing_break_out";
    from?: string;
    to?: string;
    staffId?: string;
    stationId?: string;
    limit?: number;
  }
) {
  const sp = new URLSearchParams();
  if (params.status) sp.set("status", params.status);
  if (params.caseType) sp.set("caseType", params.caseType);
  if (params.from) sp.set("from", params.from);
  if (params.to) sp.set("to", params.to);
  if (params.staffId) sp.set("staffId", params.staffId);
  if (params.stationId) sp.set("stationId", params.stationId);
  if (params.limit != null) sp.set("limit", String(params.limit));

  const q = sp.toString();
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-audit${q ? `?${q}` : ""}`, {
    method: "GET",
    headers: { ...getSupabaseGatewayHeaders(), "x-ams-access-token": accessToken }
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

export async function companyAuditSetStatus(accessToken: string, input: { caseId: string; status: "open" | "resolved" | "dismissed" }) {
  const res = await fetch(`${getAmsFunctionsBaseUrl()}/company-audit?action=set-status`, {
    method: "POST",
    headers: { ...getSupabaseGatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken },
    body: JSON.stringify(input)
  });
  const json = await readJson(res);
  handleAmsJsonResponse(res, json);
  return json.result as any;
}

