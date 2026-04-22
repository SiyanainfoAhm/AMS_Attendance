export function getSupabaseUrl(): string {
  const v = import.meta.env.VITE_SUPABASE_URL as string | undefined;
  if (!v) throw new Error("Missing VITE_SUPABASE_URL");
  return v;
}

export function getSupabaseAnonKey(): string {
  const v = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;
  if (!v) throw new Error("Missing VITE_SUPABASE_ANON_KEY");
  return v;
}

export function getAmsFunctionsBaseUrl(): string {
  return `${getSupabaseUrl()}/functions/v1`;
}

