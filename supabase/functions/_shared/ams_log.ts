/** Single-line JSON logs for Supabase Edge log drains / external monitoring. */
export function logAmsEdge(
  fn: string,
  level: "info" | "warn" | "error",
  payload: Record<string, unknown>
): void {
  console.log(JSON.stringify({ ts: new Date().toISOString(), level, fn, ...payload }));
}
