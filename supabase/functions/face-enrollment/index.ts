import { tryGetServiceClient } from "../_shared/supabase.ts";
import { getAmsAccessToken, jsonResponse, optionsResponse } from "../_shared/http.ts";
import { ensureCollection, getRekognitionConfig, indexFaceBase64 } from "../_shared/rekognition.ts";

function safeBase64(s: unknown): string | null {
  if (typeof s !== "string") return null;
  const v = s.trim();
  if (!v) return null;
  // allow data URL
  const m = v.match(/^data:image\/[a-zA-Z0-9.+-]+;base64,(.*)$/);
  return m ? m[1] : v;
}

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
  const action = (url.searchParams.get("action") ?? "").trim();

  if (req.method === "GET" && action === "status") {
    const staffId = (url.searchParams.get("staffId") ?? "").trim() || null;
    if (!staffId) return jsonResponse({ error: "staff_id_required" }, { status: 400 });

    const { data: prof, error } = await svc.client
      .from("ams_staff_face_profile")
      .select("status,enrolled_face_count")
      .eq("ams_company_id", session.company_id)
      .eq("ams_staff_id", staffId)
      .maybeSingle();
    if (error) return jsonResponse({ error: "db_error", details: error.message }, { status: 500 });

    return jsonResponse({ ok: true, result: prof ?? { status: "pending", enrolled_face_count: 0 } });
  }

  if (req.method === "POST" && action === "enroll") {
    const body = await req.json().catch(() => null);
    const staffId = (body?.staffId ?? "").toString().trim();
    const selfieBase64 = safeBase64(body?.selfieBase64);
    if (!staffId) return jsonResponse({ error: "staff_id_required" }, { status: 400 });
    if (!selfieBase64) return jsonResponse({ error: "selfie_required" }, { status: 400 });

    // Load company Rekognition config (region + collection id)
    const { data: settings, error: sErr } = await svc.client
      .from("ams_company_settings")
      .select("rekognition_region,rekognition_collection_id")
      .eq("ams_company_id", session.company_id)
      .maybeSingle();
    if (sErr) return jsonResponse({ error: "db_error", details: sErr.message }, { status: 500 });

    const region = (settings?.rekognition_region ?? "").toString().trim() || null;
    const collectionId =
      (settings?.rekognition_collection_id ?? "").toString().trim() || `ams_${session.company_id?.replaceAll("-", "")}`;

    const cfg = (() => {
      try {
        return getRekognitionConfig(region);
      } catch (e) {
        return { error: `${e}` } as const;
      }
    })();
    if ("error" in cfg) return jsonResponse({ error: "aws_not_configured", details: cfg.error }, { status: 500 });

    const coll = await ensureCollection(cfg, collectionId);
    if (!coll.ok) return jsonResponse({ error: "rekognition_error", details: coll.error }, { status: coll.status });

    // Persist collection id to company settings if missing (best-effort)
    if (!settings?.rekognition_collection_id) {
      await svc.client
        .from("ams_company_settings")
        .update({ rekognition_collection_id: collectionId, rekognition_region: cfg.region })
        .eq("ams_company_id", session.company_id);
    }

    const idx = await indexFaceBase64(cfg, collectionId, selfieBase64, staffId);
    if (!idx.ok) return jsonResponse({ error: "rekognition_error", details: idx.error }, { status: idx.status });

    const faceId = idx.data.FaceRecords?.[0]?.Face?.FaceId ?? null;
    if (!faceId) {
      return jsonResponse({ error: "no_face_indexed", details: idx.data }, { status: 400 });
    }

    // Upsert profile + insert vector
    await svc.client
      .from("ams_staff_face_profile")
      .upsert(
        {
          ams_company_id: session.company_id,
          ams_staff_id: staffId,
          status: "pending"
        },
        { onConflict: "ams_company_id,ams_staff_id" }
      );

    const { error: vErr } = await svc.client.from("ams_staff_face_vector").insert({
      ams_company_id: session.company_id,
      ams_staff_id: staffId,
      rekognition_face_id: faceId,
      is_active: true,
      meta_json: { source: "enrollment" }
    });
    if (vErr) {
      return jsonResponse({ error: "db_error", details: vErr.message }, { status: 500 });
    }

    const { count: newCountMaybe, error: cErr } = await svc.client
      .from("ams_staff_face_vector")
      .select("id", { count: "exact", head: true })
      .eq("ams_company_id", session.company_id)
      .eq("ams_staff_id", staffId)
      .eq("is_active", true);
    if (cErr) return jsonResponse({ error: "db_error", details: cErr.message }, { status: 500 });

    const newCount = Math.max(0, newCountMaybe ?? 0);
    const status = newCount >= 3 ? "active" : "pending";

    await svc.client
      .from("ams_staff_face_profile")
      .update({ enrolled_face_count: newCount, status })
      .eq("ams_company_id", session.company_id)
      .eq("ams_staff_id", staffId);

    return jsonResponse({ ok: true, result: { status, enrolled_face_count: newCount, faceId } });
  }

  return jsonResponse({ error: "method_not_allowed" }, { status: 405 });
});

