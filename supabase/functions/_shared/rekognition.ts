import { signAwsRequest } from "./aws_sigv4.ts";

function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`missing_env:${name}`);
  return v;
}

function envOrNull(name: string): string | null {
  const v = Deno.env.get(name);
  return v && v.length ? v : null;
}

export type RekognitionConfig = {
  region: string;
  accessKeyId: string;
  secretAccessKey: string;
  sessionToken?: string | null;
};

export function getRekognitionConfig(regionOverride?: string | null): RekognitionConfig {
  return {
    region: (regionOverride && regionOverride.trim()) || env("AWS_REGION"),
    accessKeyId: env("AWS_ACCESS_KEY_ID"),
    secretAccessKey: env("AWS_SECRET_ACCESS_KEY"),
    sessionToken: envOrNull("AWS_SESSION_TOKEN")
  };
}

async function rekognitionCall<T>(
  cfg: RekognitionConfig,
  target: string,
  body: Record<string, unknown>
): Promise<{ ok: true; data: T } | { ok: false; error: string; status: number; details?: unknown }> {
  const url = `https://rekognition.${cfg.region}.amazonaws.com/`;
  const req = new Request(url, {
    method: "POST",
    headers: {
      "content-type": "application/x-amz-json-1.1",
      "x-amz-target": target
    },
    body: JSON.stringify(body)
  });

  const signed = await signAwsRequest(req, {
    accessKeyId: cfg.accessKeyId,
    secretAccessKey: cfg.secretAccessKey,
    sessionToken: cfg.sessionToken,
    region: cfg.region,
    service: "rekognition"
  });

  const res = await fetch(signed);
  const text = await res.text();
  const json = (() => {
    try {
      return JSON.parse(text);
    } catch (_) {
      return null;
    }
  })();

  if (!res.ok) {
    const msg = (json && (json.message || json.Message || json.__type)) ? `${json.message || json.Message || json.__type}` : text;
    return { ok: false, error: msg || "rekognition_error", status: res.status, details: json ?? text };
  }

  return { ok: true, data: (json ?? {}) as T };
}

export async function ensureCollection(cfg: RekognitionConfig, collectionId: string) {
  const out = await rekognitionCall<{ StatusCode?: number }>(cfg, "RekognitionService.CreateCollection", {
    CollectionId: collectionId
  });
  // CreateCollection is idempotent-ish; if already exists AWS returns 409/ResourceAlreadyExistsException in some regions.
  if (out.ok) return out;
  if (String(out.error).includes("ResourceAlreadyExists")) return { ok: true as const, data: { StatusCode: 200 } };
  return out;
}

export type IndexFacesResult = {
  FaceRecords?: Array<{ Face?: { FaceId?: string } }>;
  UnindexedFaces?: unknown[];
};

export async function indexFaceBase64(
  cfg: RekognitionConfig,
  collectionId: string,
  imageBase64: string,
  externalImageId?: string
) {
  return await rekognitionCall<IndexFacesResult>(cfg, "RekognitionService.IndexFaces", {
    CollectionId: collectionId,
    Image: { Bytes: imageBase64 },
    ExternalImageId: externalImageId,
    QualityFilter: "AUTO",
    MaxFaces: 1,
    DetectionAttributes: []
  });
}

export type SearchFacesByImageResult = {
  FaceMatches?: Array<{ Similarity?: number; Face?: { FaceId?: string } }>;
};

export async function searchFacesByImageBase64(cfg: RekognitionConfig, collectionId: string, imageBase64: string) {
  return await rekognitionCall<SearchFacesByImageResult>(cfg, "RekognitionService.SearchFacesByImage", {
    CollectionId: collectionId,
    Image: { Bytes: imageBase64 },
    FaceMatchThreshold: 0,
    MaxFaces: 5
  });
}

