import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Layout } from "../components/Layout";
import { useAuth } from "../../auth/AuthContext";
import { companyDailyAttendanceReport, companyOrgList, companyStaffList } from "../../lib/amsApi";

type StaffOpt = { id: string; label: string };
type StationOpt = { id: string; label: string };

type DailyRow = {
  shift_date: string;
  staff_id: string;
  staff_code: string;
  full_name: string;
  station_id: string | null;
  station_code: string | null;
  station_name: string | null;
  last_punch_type: string | null;
  first_punch_at: string | null;
  last_punch_at: string | null;
  total_work_minutes: number;
  total_break_minutes: number;
  total_active_minutes: number;
  missing_out?: boolean;
  missing_break_out?: boolean;
};

function defaultTo(): string {
  return new Date().toISOString().slice(0, 10);
}

function defaultFrom(): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - 6);
  return d.toISOString().slice(0, 10);
}

function csvEscape(s: string) {
  return `"${String(s ?? "").replace(/"/g, '""')}"`;
}

function downloadCsv(filename: string, lines: string[][]) {
  const body = lines.map((row) => row.map(csvEscape).join(",")).join("\n");
  const blob = new Blob([body], { type: "text/csv;charset=utf-8" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = filename;
  a.click();
  URL.revokeObjectURL(a.href);
}

function fmtMin(min: number | null | undefined) {
  const m = Math.max(0, Number(min ?? 0));
  const h = Math.floor(m / 60);
  const mm = m % 60;
  return `${h}h ${String(mm).padStart(2, "0")}m`;
}

export function DailyAttendanceReportPage() {
  const { state } = useAuth();
  const nav = useNavigate();

  const [from, setFrom] = useState(defaultFrom);
  const [to, setTo] = useState(defaultTo);
  const [staffId, setStaffId] = useState<string>("");
  const [stationId, setStationId] = useState<string>("");

  const [staffOpts, setStaffOpts] = useState<StaffOpt[]>([]);
  const [stationOpts, setStationOpts] = useState<StationOpt[]>([]);

  const [rows, setRows] = useState<DailyRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!state.accessToken) {
      nav("/login");
      return;
    }
    if (!state.companyId) nav("/select-company");
  }, [nav, state.accessToken, state.companyId]);

  useEffect(() => {
    async function loadMeta() {
      if (!state.accessToken) return;
      try {
        const [staffRes, stationsRes] = await Promise.all([
          companyStaffList(state.accessToken, { page: 1, pageSize: 200, includeMeta: false }),
          companyOrgList(state.accessToken, "stations", { page: 1, pageSize: 500 }),
        ]);
        const staffItems = (staffRes.items ?? []).map((s: any) => ({
          id: String(s.id),
          label: `${s.full_name ?? s.fullName ?? "—"} (${s.staff_code ?? s.staffCode ?? "—"})`,
        }));
        const stationItems = (stationsRes.items ?? []).map((st: any) => ({
          id: String(st.id),
          label: `${st.name ?? "—"} (${st.code ?? "—"})`,
        }));
        setStaffOpts(staffItems);
        setStationOpts(stationItems);
      } catch (e) {
        // non-fatal
      }
    }
    if (state.accessToken && state.companyId) void loadMeta();
  }, [state.accessToken, state.companyId]);

  async function load() {
    if (!state.accessToken) return;
    setLoading(true);
    setError(null);
    try {
      const res = await companyDailyAttendanceReport(state.accessToken, {
        from,
        to,
        staffId: staffId || undefined,
        stationId: stationId || undefined,
      });
      const items = (res?.items ?? res?.result?.items ?? res?.items) as DailyRow[] | undefined;
      setRows(Array.isArray(items) ? items : []);
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

  const exportRows = useMemo(() => {
    const lines: string[][] = [];
    lines.push([
      "shift_date",
      "staff_code",
      "full_name",
      "station_code",
      "station_name",
      "last_punch_type",
      "total_work_minutes",
      "total_break_minutes",
      "total_active_minutes",
      "missing_out",
      "missing_break_out",
    ]);
    for (const r of rows) {
      lines.push([
        String(r.shift_date ?? ""),
        String(r.staff_code ?? ""),
        String(r.full_name ?? ""),
        String(r.station_code ?? ""),
        String(r.station_name ?? ""),
        String(r.last_punch_type ?? ""),
        String(r.total_work_minutes ?? 0),
        String(r.total_break_minutes ?? 0),
        String(r.total_active_minutes ?? 0),
        String(Boolean(r.missing_out)),
        String(Boolean(r.missing_break_out)),
      ]);
    }
    return lines;
  }, [rows]);

  return (
    <Layout>
      <div className="page-stack">
        <div className="page-head">
          <div className="page-head-text">
            <h1 className="page-title">Daily attendance report</h1>
            <p className="page-subtitle">Active hours, break time, and missing punch flags</p>
          </div>
          <div className="page-actions date-toolbar filter-toolbar" style={{ gap: "var(--space-2)" }}>
            <input className="input input-date" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
            <span className="muted" style={{ whiteSpace: "nowrap" }}>
              to
            </span>
            <input className="input input-date" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
            <select className="select" value={staffId} onChange={(e) => setStaffId(e.target.value)}>
              <option value="">All staff</option>
              {staffOpts.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.label}
                </option>
              ))}
            </select>
            <select className="select" value={stationId} onChange={(e) => setStationId(e.target.value)}>
              <option value="">All stations</option>
              {stationOpts.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.label}
                </option>
              ))}
            </select>
            <button type="button" className="btn btn-primary" onClick={() => void load()} disabled={loading}>
              Run report
            </button>
            <button
              type="button"
              className="btn btn-secondary"
              disabled={loading || rows.length === 0}
              onClick={() => downloadCsv(`daily-attendance-${from}_${to}.csv`, exportRows)}
            >
              Export CSV
            </button>
          </div>
        </div>

        {error && <div className="alert alert-error">{error}</div>}

        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Staff</th>
                <th>Station</th>
                <th>Last</th>
                <th>Total</th>
                <th>Break</th>
                <th>Active</th>
                <th>Flags</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={`${r.shift_date}-${r.staff_id}-${i}`}>
                  <td>{r.shift_date}</td>
                  <td>
                    <div className="cell-strong">{r.full_name}</div>
                    <div className="cell-muted">{r.staff_code}</div>
                  </td>
                  <td>{r.station_name ? `${r.station_name} (${r.station_code ?? ""})` : r.station_id ?? "—"}</td>
                  <td className="cell-strong">{(r.last_punch_type ?? "—").toUpperCase()}</td>
                  <td>{fmtMin(r.total_work_minutes)}</td>
                  <td>{fmtMin(r.total_break_minutes)}</td>
                  <td className="cell-strong">{fmtMin(r.total_active_minutes)}</td>
                  <td>
                    {(r.missing_out ? "Missing OUT" : "") || (r.missing_break_out ? "Missing BREAK OUT" : "") || "—"}
                  </td>
                </tr>
              ))}
              {rows.length === 0 && (
                <tr>
                  <td colSpan={8} className="cell-muted" style={{ padding: "var(--space-4)" }}>
                    {loading ? "Loading…" : "No rows in range"}
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

