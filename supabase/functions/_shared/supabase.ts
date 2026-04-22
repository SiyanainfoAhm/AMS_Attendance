import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

function getEnvOrNull(name: string): string | null {
  const v = Deno.env.get(name);
  return v && v.length > 0 ? v : null;
}

export function tryGetServiceClient():
  | { ok: true; client: ReturnType<typeof createClient> }
  | { ok: false; error: string } {
  const url = getEnvOrNull("SUPABASE_URL");
  const key = getEnvOrNull("SUPABASE_SERVICE_ROLE_KEY");
  if (!url) return { ok: false, error: "missing_env:SUPABASE_URL" };
  if (!key) return { ok: false, error: "missing_env:SUPABASE_SERVICE_ROLE_KEY" };

  return {
    ok: true,
    client: createClient(url, key, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
    })
  };
}

