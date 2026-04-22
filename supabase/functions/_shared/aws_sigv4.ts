function toHex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function utf8(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

async function sha256Hex(data: string | Uint8Array): Promise<string> {
  const bytes = typeof data === "string" ? utf8(data) : data;
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return toHex(hash);
}

async function hmacSha256(key: Uint8Array, data: string): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, utf8(data));
  return new Uint8Array(sig);
}

function amzDate(now = new Date()): { amz: string; short: string } {
  const yyyy = now.getUTCFullYear().toString();
  const mm = (now.getUTCMonth() + 1).toString().padStart(2, "0");
  const dd = now.getUTCDate().toString().padStart(2, "0");
  const hh = now.getUTCHours().toString().padStart(2, "0");
  const mi = now.getUTCMinutes().toString().padStart(2, "0");
  const ss = now.getUTCSeconds().toString().padStart(2, "0");
  const short = `${yyyy}${mm}${dd}`;
  const amz = `${short}T${hh}${mi}${ss}Z`;
  return { amz, short };
}

function normalizeHeaderValue(v: string): string {
  return v.trim().replace(/\s+/g, " ");
}

function canonicalHeaders(headers: Headers): { canonical: string; signedHeaders: string } {
  const pairs: Array<[string, string]> = [];
  headers.forEach((value, key) => {
    pairs.push([key.toLowerCase(), normalizeHeaderValue(value)]);
  });
  pairs.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  const canonical = pairs.map(([k, v]) => `${k}:${v}\n`).join("");
  const signedHeaders = pairs.map(([k]) => k).join(";");
  return { canonical, signedHeaders };
}

function canonicalQueryString(url: URL): string {
  const params = [...url.searchParams.entries()]
    .map(([k, v]) => [encodeURIComponent(k), encodeURIComponent(v)] as const)
    .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0));
  return params.map(([k, v]) => `${k}=${v}`).join("&");
}

async function deriveSigningKey(secretKey: string, shortDate: string, region: string, service: string): Promise<Uint8Array> {
  const kDate = await hmacSha256(utf8(`AWS4${secretKey}`), shortDate);
  const kRegion = await hmacSha256(kDate, region);
  const kService = await hmacSha256(kRegion, service);
  const kSigning = await hmacSha256(kService, "aws4_request");
  return kSigning;
}

export type AwsSigV4Config = {
  accessKeyId: string;
  secretAccessKey: string;
  sessionToken?: string | null;
  region: string;
  service: string;
};

export async function signAwsRequest(req: Request, cfg: AwsSigV4Config): Promise<Request> {
  const url = new URL(req.url);
  const method = req.method.toUpperCase();
  const { amz, short } = amzDate();

  const headers = new Headers(req.headers);
  headers.set("host", url.host);
  headers.set("x-amz-date", amz);
  if (cfg.sessionToken) headers.set("x-amz-security-token", cfg.sessionToken);

  const bodyText = req.body ? await req.clone().text() : "";
  const payloadHash = await sha256Hex(bodyText);
  headers.set("x-amz-content-sha256", payloadHash);

  const { canonical: canonHeaders, signedHeaders } = canonicalHeaders(headers);
  const canonReq =
    `${method}\n` +
    `${url.pathname}\n` +
    `${canonicalQueryString(url)}\n` +
    `${canonHeaders}\n` +
    `${signedHeaders}\n` +
    `${payloadHash}`;

  const canonReqHash = await sha256Hex(canonReq);
  const scope = `${short}/${cfg.region}/${cfg.service}/aws4_request`;
  const stringToSign = `AWS4-HMAC-SHA256\n${amz}\n${scope}\n${canonReqHash}`;

  const signingKey = await deriveSigningKey(cfg.secretAccessKey, short, cfg.region, cfg.service);
  const sig = await hmacSha256(signingKey, stringToSign);
  const signature = toHex(sig.buffer);

  const authorization =
    `AWS4-HMAC-SHA256 Credential=${cfg.accessKeyId}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;
  headers.set("authorization", authorization);

  return new Request(req.url, { method, headers, body: bodyText.length ? bodyText : undefined });
}

