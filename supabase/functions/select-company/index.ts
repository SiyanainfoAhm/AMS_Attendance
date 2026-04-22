import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, jsonResponse, optionsResponse } from "../_shared/http.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse();
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, { status: 405 });

  const accessToken = getAmsAccessToken(req);
  if (!accessToken) return jsonResponse({ error: "missing_access_token" }, { status: 401 });

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, { status: 400 });
  }

  const { companyId } = (body ?? {}) as Record<string, unknown>;
  if (typeof companyId !== "string" || companyId.length < 8) {
    return jsonResponse({ error: "companyId_required" }, { status: 400 });
  }

  const svc = tryGetServiceClient();
  if (!svc.ok) return jsonResponse({ error: "server_misconfigured", details: svc.error }, { status: 500 });

  const { data, error } = await svc.client.rpc("ams_sp_select_company", {
    p_access_token: accessToken,
    p_company_id: companyId
  });

  if (error) {
    return jsonResponse({ error: "select_company_failed", details: error.message }, { status: 403 });
  }

  return jsonResponse({ ok: true, result: data });
});

