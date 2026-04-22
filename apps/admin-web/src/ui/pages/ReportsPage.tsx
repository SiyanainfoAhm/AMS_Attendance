import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Layout } from "../components/Layout";
import { useAuth } from "../../auth/AuthContext";
import { companyReportsSummary } from "../../lib/amsApi";

type ProductivityRow = { day: string; staff_punched_any: number };
type StationRow = {
  punch_day: string;
  ams_station_id: string | null;
  punch_in_count: number;
  punch_out_count: number;
  station: { code: string; name: string } | null;
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

export function ReportsPage() {
  const { state } = useAuth();
  const nav = useNavigate();
  const perms: string[] = state.me?.permissions ?? [];
  const isPlatform = state.me?.user?.is_platform_super_admin === true;
  const canExport = isPlatform || perms.includes("COMPANY_REPORT_EXPORT");

  const [from, setFrom] = useState(defaultFrom);
  const [to, setTo] = useState(defaultTo);
  const [productivity, setProductivity] = useState<ProductivityRow[]>([]);
  const [stations, setStations] = useState<StationRow[]>([]);
  const [range, setRange] = useState<{ from: string; to: string } | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!state.accessToken) {
      nav("/login");
      return;
    }
    if (!state.companyId) {
      nav("/select-company");
    }
  }, [nav, state.accessToken, state.companyId]);

  async function load() {
    if (!state.accessToken) return;
    setLoading(true);
    setError(null);
    try {
      const res = await companyReportsSummary(state.accessToken, { from, to });
      setRange(res.range ?? null);
      setProductivity(res.productivity ?? []);
      setStations(res.stationAttendance ?? []);
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
    lines.push(["section", "day", "metric", "value", "station_code", "station_name"]);
    for (const p of productivity) {
      lines.push(["productivity", String(p.day).slice(0, 10), "staff_punched_any", String(p.staff_punched_any ?? ""), "", ""]);
    }
    for (const s of stations) {
      lines.push([
        "station",
        String(s.punch_day).slice(0, 10),
        "in_out",
        `${s.punch_in_count ?? 0}/${s.punch_out_count ?? 0}`,
        s.station?.code ?? "",
        s.station?.name ?? ""
      ]);
    }
    return lines;
  }, [productivity, stations]);

  return (
    <Layout>
      <div className="page-stack">
        <div className="page-head">
          <div className="page-head-text">
            <h1 className="page-title">Reports</h1>
            <p className="page-subtitle">Attendance summaries from reporting views</p>
          </div>
          <div className="page-actions date-toolbar filter-toolbar">
            <input className="input input-date" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
            <span className="muted" style={{ whiteSpace: "nowrap" }}>
              to
            </span>
            <input className="input input-date" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
            <button type="button" className="btn btn-primary" onClick={() => void load()} disabled={loading}>
              Run report
            </button>
            {canExport && (
              <button
                type="button"
                className="btn btn-secondary"
                disabled={loading || (!productivity.length && !stations.length)}
                onClick={() => downloadCsv(`ams-report-${range?.from ?? from}_${range?.to ?? to}.csv`, exportRows)}
              >
                Export CSV
              </button>
            )}
          </div>
        </div>

        <div className="card" style={{ padding: "var(--space-3)" }}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "var(--space-3)" }}>
            <div>
              <div className="section-title" style={{ marginBottom: "0.25rem" }}>
                Daily attendance report
              </div>
              <div className="muted">Active hours, breaks, and missing punch flags</div>
            </div>
            <button type="button" className="btn btn-secondary" onClick={() => nav("/reports/daily-attendance")}>
              Open
            </button>
          </div>
        </div>

        {range && (
          <p className="muted">
            Range: <strong>{range.from}</strong> → <strong>{range.to}</strong>
          </p>
        )}

        {error && <div className="alert alert-error">{error}</div>}

        <div>
          <h2 className="section-title">Company productivity</h2>
          <p className="muted" style={{ marginTop: "-0.5rem", marginBottom: "var(--space-3)" }}>
            Distinct staff with at least one punch per day
          </p>
          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Day</th>
                  <th>Staff (any punch)</th>
                </tr>
              </thead>
              <tbody>
                {productivity.map((p, i) => (
                  <tr key={`${p.day}-${i}`}>
                    <td>{String(p.day).slice(0, 10)}</td>
                    <td className="cell-strong">{p.staff_punched_any ?? 0}</td>
                  </tr>
                ))}
                {productivity.length === 0 && (
                  <tr>
                    <td colSpan={2} className="cell-muted" style={{ padding: "var(--space-4)" }}>
                      {loading ? "Loading…" : "No rows in range"}
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>

        <div>
          <h2 className="section-title">Station attendance</h2>
          <p className="muted" style={{ marginTop: "-0.5rem", marginBottom: "var(--space-3)" }}>
            Punch in / out counts by station and day
          </p>
          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Day</th>
                  <th>Station</th>
                  <th>In</th>
                  <th>Out</th>
                </tr>
              </thead>
              <tbody>
                {stations.map((s, i) => (
                  <tr key={`${s.punch_day}-${s.ams_station_id}-${i}`}>
                    <td>{String(s.punch_day).slice(0, 10)}</td>
                    <td>{s.station ? `${s.station.name} (${s.station.code})` : s.ams_station_id ?? "—"}</td>
                    <td>{s.punch_in_count ?? 0}</td>
                    <td>{s.punch_out_count ?? 0}</td>
                  </tr>
                ))}
                {stations.length === 0 && (
                  <tr>
                    <td colSpan={4} className="cell-muted" style={{ padding: "var(--space-4)" }}>
                      {loading ? "Loading…" : "No rows in range"}
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Layout>
  );
}
