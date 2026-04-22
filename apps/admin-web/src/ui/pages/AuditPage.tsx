import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Layout } from "../components/Layout";
import { useAuth } from "../../auth/AuthContext";
import { companyAuditList, companyAuditSetStatus } from "../../lib/amsApi";

type AuditRow = {
  id: string;
  case_type: "missing_out" | "missing_break_out" | string;
  status: "open" | "resolved" | "dismissed" | string;
  shift_date: string;
  title: string;
  description: string | null;
  payload_json: any;
  created_at: string;
  resolved_at: string | null;
  staff_id: string;
  staff_code: string | null;
  full_name: string | null;
  station_id: string | null;
  station_code: string | null;
  station_name: string | null;
};

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

function daysAgoIso(n: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
}

function typeLabel(t: string) {
  if (t === "missing_out") return "Missing OUT";
  if (t === "missing_break_out") return "Missing Break OUT";
  return t;
}

function statusPill(s: string) {
  const cls = s === "open" ? "pill pill-warn" : s === "resolved" ? "pill pill-ok" : "pill";
  return <span className={cls}>{s}</span>;
}

export function AuditPage() {
  const { state } = useAuth();
  const nav = useNavigate();

  const [from, setFrom] = useState(daysAgoIso(30));
  const [to, setTo] = useState(todayIso);
  const [status, setStatusFilter] = useState<"open" | "resolved" | "dismissed">("open");
  const [caseType, setCaseType] = useState<"" | "missing_out" | "missing_break_out">("");
  const [q, setQ] = useState("");

  const [items, setItems] = useState<AuditRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!state.accessToken) {
      nav("/login");
      return;
    }
    if (!state.companyId) nav("/select-company");
  }, [nav, state.accessToken, state.companyId]);

  async function load() {
    if (!state.accessToken) return;
    setLoading(true);
    setError(null);
    try {
      const res = await companyAuditList(state.accessToken, {
        status,
        caseType: caseType || undefined,
        from,
        to,
        limit: 300
      });
      const rows = (res.items ?? []) as AuditRow[];
      setItems(rows);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "load_failed");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (state.accessToken && state.companyId) void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.accessToken, state.companyId]);

  const filtered = useMemo(() => {
    const s = q.trim().toLowerCase();
    if (!s) return items;
    return items.filter((r) => {
      const staff = `${r.full_name ?? ""} ${r.staff_code ?? ""} ${r.staff_id ?? ""}`.toLowerCase();
      const station = `${r.station_name ?? ""} ${r.station_code ?? ""} ${r.station_id ?? ""}`.toLowerCase();
      const title = `${r.title ?? ""} ${r.description ?? ""}`.toLowerCase();
      return staff.includes(s) || station.includes(s) || title.includes(s) || String(r.shift_date ?? "").includes(s);
    });
  }, [items, q]);

  async function setCaseStatus(id: string, next: "resolved" | "dismissed" | "open") {
    if (!state.accessToken) return;
    const prev = items;
    setItems((xs) => xs.map((x) => (x.id === id ? { ...x, status: next } : x)));
    try {
      await companyAuditSetStatus(state.accessToken, { caseId: id, status: next });
      await load();
    } catch (e: unknown) {
      setItems(prev);
      setError(e instanceof Error ? e.message : "update_failed");
    }
  }

  return (
    <Layout>
      <div className="page-stack">
        <div className="page-head">
          <div className="page-head-text">
            <h1 className="page-title">Audit</h1>
            <p className="page-subtitle">Review and resolve missing punch anomalies</p>
          </div>
          <div className="page-actions date-toolbar filter-toolbar">
            <input className="input input-date" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
            <span className="muted" style={{ whiteSpace: "nowrap" }}>
              to
            </span>
            <input className="input input-date" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
            <select className="select" value={status} onChange={(e) => setStatusFilter(e.target.value as any)}>
              <option value="open">open</option>
              <option value="resolved">resolved</option>
              <option value="dismissed">dismissed</option>
            </select>
            <select className="select" value={caseType} onChange={(e) => setCaseType(e.target.value as any)}>
              <option value="">all types</option>
              <option value="missing_out">missing_out</option>
              <option value="missing_break_out">missing_break_out</option>
            </select>
            <button type="button" className="btn btn-primary" onClick={() => void load()} disabled={loading}>
              Refresh
            </button>
          </div>
        </div>

        <div className="card" style={{ padding: "var(--space-3)" }}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "var(--space-3)" }}>
            <div>
              <div className="section-title" style={{ marginBottom: "0.25rem" }}>
                Cases
              </div>
              <div className="muted">{filtered.length} shown</div>
            </div>
            <input
              className="input"
              placeholder="Search staff/station/date…"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              style={{ width: 280 }}
            />
          </div>
        </div>

        {error && <div className="alert alert-error">{error}</div>}

        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Type</th>
                <th>Status</th>
                <th>Staff</th>
                <th>Station</th>
                <th>Created</th>
                <th style={{ width: 260 }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((r) => (
                <tr key={r.id}>
                  <td className="cell-strong">{String(r.shift_date).slice(0, 10)}</td>
                  <td>{typeLabel(r.case_type)}</td>
                  <td>{statusPill(r.status)}</td>
                  <td>{r.full_name ? `${r.full_name}${r.staff_code ? ` (${r.staff_code})` : ""}` : r.staff_id}</td>
                  <td>{r.station_name ? `${r.station_name}${r.station_code ? ` (${r.station_code})` : ""}` : r.station_id ?? "—"}</td>
                  <td className="muted">{String(r.created_at).replace("T", " ").slice(0, 16)}</td>
                  <td>
                    <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                      <button
                        type="button"
                        className="btn btn-secondary btn-sm"
                        disabled={loading || r.status === "resolved"}
                        onClick={() => void setCaseStatus(r.id, "resolved")}
                      >
                        Mark resolved
                      </button>
                      <button
                        type="button"
                        className="btn btn-secondary btn-sm"
                        disabled={loading || r.status === "dismissed"}
                        onClick={() => void setCaseStatus(r.id, "dismissed")}
                      >
                        Dismiss
                      </button>
                      <button
                        type="button"
                        className="btn btn-secondary btn-sm"
                        disabled={loading || r.status === "open"}
                        onClick={() => void setCaseStatus(r.id, "open")}
                      >
                        Reopen
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr>
                  <td colSpan={7} className="cell-muted" style={{ padding: "var(--space-4)" }}>
                    {loading ? "Loading…" : "No audit cases in this range"}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </Layout>
  );
}

