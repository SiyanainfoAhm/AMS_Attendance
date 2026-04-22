import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, getBearerToken, jsonResponse, optionsResponse } from "../_shared/http.ts";

type ServiceAccount = {
  project_id: string;
  private_key: string;
  client_email: string;
  token_uri?: string;
};

function b64UrlEncode(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  // deno-lint-ignore no-deprecated-deno-api
  const b64 = btoa(bin);
  return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function textBytes(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

async function signRs256(privateKeyPem: string, message: string): Promise<string> {
  const pem = privateKeyPem.replace(/-----BEGIN PRIVATE KEY-----/g, "").replace(/-----END PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  // deno-lint-ignore no-deprecated-deno-api
  const raw = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    raw.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign({ name: "RSASSA-PKCS1-v1_5" }, key, textBytes(message));
  return b64UrlEncode(new Uint8Array(sig));
}

async function getFcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64UrlEncode(textBytes(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const payload = b64UrlEncode(
    textBytes(
      JSON.stringify({
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: sa.token_uri ?? "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 55 * 60,
      }),
    ),
  );
  const toSign = `${header}.${payload}`;
  const sig = await signRs256(sa.private_key, toSign);
  const jwt = `${toSign}.${sig}`;

  const tokenUri = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const form = new URLSearchParams();
  form.set("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer");
  form.set("assertion", jwt);

  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });
  const json = await res.json().catch(() => null);
  if (!res.ok || !json?.access_token) {
    throw new Error(`fcm_token_failed:${res.status}:${JSON.stringify(json)}`);
  }
  return String(json.access_token);
}

async function fcmSend(projectId: string, accessToken: string, pushToken: string, title: string, body?: string | null, data?: Record<string, string>) {
  const url = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`;
  const payload = {
    message: {
      token: pushToken,
      notification: {
        title,
        ...(body ? { body } : {}),
      },
      ...(data && Object.keys(data).length ? { data } : {}),
      android: { priority: "HIGH" },
    },
  };
  const res = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `Bearer ${accessToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  const json = await res.json().catch(() => null);
  return { ok: res.ok, status: res.status, json };
}

function fcmDataFromPayload(payload: unknown): Record<string, string> {
  if (!payload || typeof payload !== "object") return {};
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(payload as Record<string, unknown>)) {
    if (v == null) continue;
    if (typeof v === "string" || typeof v === "number" || typeof v === "boolean") {
      out[k] = String(v);
      continue;
    }
    try {
      out[k] = JSON.stringify(v);
    } catch {
      // ignore
    }
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return optionsResponse();

  const svc = tryGetServiceClient();
  if (!svc.ok) return jsonResponse({ error: "server_misconfigured", details: svc.error }, { status: 500 });

  const dispatchSecret = (Deno.env.get("NOTIFICATIONS_DISPATCH_SECRET") ?? "").trim();
  const hdrSecret =
    (req.headers.get("x-ams-dispatch-secret") ?? req.headers.get("x-notifications-dispatch-secret") ?? "").trim();
  const bearer = (getBearerToken(req) ?? "").trim();
  const serviceRole = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();

  const isTrustedDispatch =
    (dispatchSecret.length > 0 && hdrSecret.length > 0 && hdrSecret === dispatchSecret) ||
    (serviceRole.length > 0 && bearer.length > 0 && bearer === serviceRole);

  if (!isTrustedDispatch) {
    const accessToken = getAmsAccessToken(req);
    if (!accessToken) return jsonResponse({ error: "missing_access_token" }, { status: 401 });

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
    if (!user.is_platform_super_admin) return jsonResponse({ error: "forbidden" }, { status: 403 });
  }

  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, { status: 405 });

  const body = await req.json().catch(() => null);
  const limit = Math.min(200, Math.max(1, Number(body?.limit ?? 50)));
  const dryRun = Boolean(body?.dryRun);

  const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";
  if (!saRaw.trim()) {
    return jsonResponse({ error: "server_misconfigured", details: "missing_FIREBASE_SERVICE_ACCOUNT_JSON" }, { status: 500 });
  }
  const sa = JSON.parse(saRaw) as ServiceAccount;
  if (!sa?.project_id || !sa?.private_key || !sa?.client_email) {
    return jsonResponse({ error: "server_misconfigured", details: "invalid_service_account_json" }, { status: 500 });
  }

  const { data: rows, error } = await svc.client
    .from("ams_notification")
    .select("id,ams_company_id,ams_user_id,title,body,created_at,status,notif_type,payload_json")
    .eq("status", "queued")
    .order("created_at", { ascending: true })
    .limit(limit);

  if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });
  const items = (rows ?? []) as any[];
  if (items.length === 0) return jsonResponse({ ok: true, result: { dispatched: 0, dryRun, configured: true } });

  let accessTokenFcm: string;
  try {
    accessTokenFcm = await getFcmAccessToken(sa);
  } catch (e) {
    return jsonResponse({ error: "fcm_auth_failed", details: String(e?.message ?? e) }, { status: 500 });
  }

  const now = new Date().toISOString();
  let sent = 0;
  let failed = 0;
  let tokenDisabled = 0;

  for (const n of items) {
    const { data: tokens, error: tokErr } = await svc.client
      .from("ams_push_token")
      .select("id,push_token,is_enabled")
      .eq("ams_company_id", n.ams_company_id)
      .eq("ams_user_id", n.ams_user_id)
      .eq("is_enabled", true)
      .order("updated_at", { ascending: false })
      .limit(5);

    if (tokErr) {
      failed++;
      await svc.client.from("ams_notification").update({ status: "failed", updated_at: now }).eq("id", n.id);
      continue;
    }

    const pushTokens = (tokens ?? []).map((t: any) => String(t.push_token)).filter(Boolean);
    if (pushTokens.length === 0) {
      failed++;
      await svc.client.from("ams_notification").update({ status: "failed", updated_at: now }).eq("id", n.id);
      continue;
    }

    const payloadData = fcmDataFromPayload(n.payload_json);
    const data = {
      ...payloadData,
      notifId: String(n.id),
      type: String(n.notif_type ?? "generic"),
    };

    let anyOk = false;
    let lastErr: any = null;

    for (const pt of pushTokens) {
      if (dryRun) {
        anyOk = true;
        continue;
      }
      const r = await fcmSend(sa.project_id, accessTokenFcm, pt, String(n.title ?? ""), n.body ?? null, data);
      if (r.ok) {
        anyOk = true;
      } else {
        lastErr = r;
        // Disable invalid tokens (common FCM errors: UNREGISTERED / INVALID_ARGUMENT)
        const msg = JSON.stringify(r.json ?? {});
        if (r.status === 404 || msg.includes("UNREGISTERED") || msg.includes("registration token is not a valid FCM registration token")) {
          tokenDisabled++;
          await svc.client.from("ams_push_token").update({ is_enabled: false, updated_at: now }).eq("push_token", pt);
        }
      }
    }

    if (anyOk) {
      sent++;
      await svc.client.from("ams_notification").update({ status: "sent", sent_at: now, updated_at: now }).eq("id", n.id);
    } else {
      failed++;
      await svc.client.from("ams_notification").update({ status: "failed", updated_at: now }).eq("id", n.id);
      if (lastErr) {
        await svc.client.from("ams_issue_log").insert({
          id: crypto.randomUUID(),
          ams_company_id: n.ams_company_id,
          issue_type: "push_send_failed",
          severity: "medium",
          message: "FCM send failed",
          context_json: { notifId: n.id, details: lastErr },
        }).catch(() => null);
      }
    }
  }

  return jsonResponse({
    ok: true,
    result: {
      dispatched: items.length,
      sent,
      failed,
      tokenDisabled,
      dryRun,
      configured: true,
    }
  });
});

