import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useAuth } from "../../auth/AuthContext";
import { Layout } from "../components/Layout";
import { companyAttendanceList, companyOrgList, companyReportsSummary, companyStaffList } from "../../lib/amsApi";

type StatCard = { label: string; value: string | number; to?: string };

type ProductivityRow = { day: string; staff_punched_any: number };
type StationRow = {
  punch_day: string;
  ams_station_id: string | null;
  punch_in_count: number;
  punch_out_count: number;
  station: { code: string; name: string } | null;
};

function utcToday(): string {
  return new Date().toISOString().slice(0, 10);
}

function utcDaysAgo(n: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
}

function fmtDayLabel(yyyyMmDd: string) {
  const d = new Date(`${yyyyMmDd}T00:00:00.000Z`);
  const wk = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getUTCDay()];
  return `${wk} ${String(d.getUTCDate()).padStart(2, "0")}`;
}

function BarSpark(props: { values: number[] }) {
  const w = 260;
  const h = 64;
  const pad = 6;
  const vals = props.values.length ? props.values : [0];
  const max = Math.max(1, ...vals);
  const bw = (w - pad * 2) / vals.length;
  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} aria-hidden>
      {vals.map((v, i) => {
        const bh = Math.max(2, Math.round(((h - pad * 2) * v) / max));
        const x = pad + i * bw + 2;
        const y = h - pad - bh;
        const rw = Math.max(6, bw - 4);
        return <rect key={i} x={x} y={y} width={rw} height={bh} rx={6} fill="currentColor" opacity={0.85} />;
      })}
    </svg>
  );
}

export function DashboardPage() {
  const { state, refreshMe } = useAuth();
  const nav = useNavigate();
  const [error, setError] = useState<string | null>(null);
  const [stats, setStats] = useState<StatCard[]>([]);
  const [loading, setLoading] = useState(false);
  const [productivity, setProductivity] = useState<ProductivityRow[]>([]);
  const [stations, setStations] = useState<StationRow[]>([]);

  const companyId = state.companyId;
  const selectedCompanyName =
    state.me?.selectedCompany?.name ??
    (Array.isArray(state.me?.companies)
      ? state.me.companies.find((c: any) => String(c?.id ?? c?.company_id ?? "") === String(companyId ?? ""))?.name ??
        state.me.companies.find((c: any) => String(c?.id ?? c?.company_id ?? "") === String(companyId ?? ""))?.company_name
      : null);
  const companyLabel = selectedCompanyName ? String(selectedCompanyName) : (companyId ?? "");

  useEffect(() => {
    (async () => {
      if (!state.accessToken) {
        nav("/login");
        return;
      }
      if (!state.companyId) {
        nav("/select-company");
        return;
      }
      setError(null);
      setLoading(true);
      let me: Awaited<ReturnType<typeof refreshMe>> | null = null;
      try {
        me = await refreshMe();
      } catch (e: unknown) {
        setError(e instanceof Error ? e.message : "me_failed");
        setLoading(false);
        return;
      }

      const perms: string[] = me?.permissions ?? [];
      const isPlatform = me?.user?.is_platform_super_admin === true;
      const token = state.accessToken;
      const cards: StatCard[] = [];

      try {
        if (isPlatform || perms.includes("COMPANY_STAFF_READ")) {
          const r = await companyStaffList(token, { page: 1, pageSize: 1 });
          cards.push({ label: "Staff", value: r.total ?? 0, to: "/staff" });
        }
      } catch {
        /* ignore */
      }

      try {
        if (isPlatform || perms.includes("COMPANY_ATTENDANCE_READ")) {
          const r = await companyAttendanceList(token, { page: 1, pageSize: 1 });
          cards.push({ label: "Punches", value: r.total ?? 0, to: "/attendance" });
        }
      } catch {
        /* ignore */
      }

      try {
        if (isPlatform || perms.includes("COMPANY_ORG_READ")) {
          const r = await companyOrgList(token, "stations", { page: 1, pageSize: 1 });
          cards.push({ label: "Stations", value: r.total ?? 0, to: "/org" });
        }
      } catch {
        /* ignore */
      }

      try {
        if (isPlatform || perms.includes("COMPANY_REPORT_READ")) {
          const to = utcToday();
          const from = utcDaysAgo(6);
          const r = await companyReportsSummary(token, { from, to });
          setProductivity((r.productivity ?? []) as ProductivityRow[]);
          setStations((r.stationAttendance ?? []) as StationRow[]);
        } else {
          setProductivity([]);
          setStations([]);
        }
      } catch {
        setProductivity([]);
        setStations([]);
      }

      setStats(cards);
      setLoading(false);
    })();
  }, [nav, refreshMe, state.accessToken, state.companyId]);

  const displayName = state.me?.user?.display_name ?? state.me?.user?.email ?? "User";
  const shortcutPerms: string[] = state.me?.permissions ?? [];
  const shortcutPlatform = state.me?.user?.is_platform_super_admin === true;

  const prodSeries = useMemo(() => {
    const map = new Map<string, number>();
    for (const p of productivity) map.set(String(p.day).slice(0, 10), Number(p.staff_punched_any ?? 0));
    const days = Array.from({ length: 7 }, (_, i) => utcDaysAgo(6 - i));
    return days.map((d) => ({ day: d, v: map.get(d) ?? 0 }));
  }, [productivity]);

  const prodMax = useMemo(() => Math.max(0, ...prodSeries.map((x) => x.v)), [prodSeries]);
  const prodToday = prodSeries.length ? prodSeries[prodSeries.length - 1].v : 0;
  const prodAvg = prodSeries.length ? Math.round(prodSeries.reduce((a, b) => a + b.v, 0) / prodSeries.length) : 0;

  const topStations = useMemo(() => {
    const agg = new Map<string, { name: string; code: string; inCount: number; outCount: number }>();
    for (const s of stations) {
      const id = s.ams_station_id ?? "—";
      const ex = agg.get(id) ?? { name: s.station?.name ?? "Unknown", code: s.station?.code ?? "—", inCount: 0, outCount: 0 };
      ex.inCount += Number(s.punch_in_count ?? 0);
      ex.outCount += Number(s.punch_out_count ?? 0);
      agg.set(id, ex);
    }
    return [...agg.entries()]
      .map(([id, v]) => ({ id, ...v, total: v.inCount + v.outCount }))
      .sort((a, b) => b.total - a.total)
      .slice(0, 5);
  }, [stations]);

  return (
    <Layout>
      <div className="page-stack">
        <div className="dash-hero">
          <div className="dash-hero-text">
            <div className="dash-hero-kicker">Welcome back</div>
            <h1 className="dash-hero-title">Dashboard</h1>
            <p className="dash-hero-subtitle">
              Signed in as <strong>{displayName}</strong>
              {companyId && (
                <>
                  {" "}
                  · company <code>{companyLabel}</code>
                </>
              )}
            </p>
          </div>
          <div className="dash-hero-actions">
            <Link to="/attendance" className="btn btn-primary">
              Punches
            </Link>
            <Link to="/reports" className="btn btn-secondary">
              Reports
            </Link>
          </div>
        </div>

        {error && <div className="alert alert-error">{error}</div>}
        {loading && <p className="muted">Loading overview…</p>}

        <div className="dash-kpi-grid">
          {stats.map((s) =>
            s.to ? (
              <Link key={s.label} to={s.to} className="dash-kpi-card">
                <div className="dash-kpi-label">{s.label}</div>
                <div className="dash-kpi-value">{s.value}</div>
                <div className="dash-kpi-hint">Open</div>
              </Link>
            ) : (
              <div key={s.label} className="dash-kpi-card" style={{ cursor: "default" }}>
                <div className="dash-kpi-label">{s.label}</div>
                <div className="dash-kpi-value">{s.value}</div>
              </div>
            )
          )}

          {(shortcutPlatform || shortcutPerms.includes("COMPANY_REPORT_READ")) && (
            <div className="dash-kpi-card dash-kpi-accent" style={{ cursor: "default" }}>
              <div className="dash-kpi-label">Today productivity</div>
              <div className="dash-kpi-value">{prodToday}</div>
              <div className="dash-kpi-meta">
                <span className="pill">7‑day avg {prodAvg}</span>
                <span className="pill">max {prodMax}</span>
              </div>
              <div className="dash-kpi-chart">
                <BarSpark values={prodSeries.map((x) => x.v)} />
              </div>
            </div>
          )}
        </div>

        {(shortcutPlatform || shortcutPerms.includes("COMPANY_REPORT_READ")) && (
          <div className="dash-grid-2">
            <div className="card dash-card">
              <div className="dash-card-head">
                <div>
                  <div className="dash-card-title">7‑day productivity</div>
                  <div className="muted">Distinct staff with at least one punch per day (UTC)</div>
                </div>
                <Link to="/reports" className="btn btn-secondary btn-sm">
                  Open reports
                </Link>
              </div>
              <div className="dash-bars">
                {prodSeries.map((x) => (
                  <div key={x.day} className="dash-bar">
                    <div className="dash-bar-col" title={`${x.v}`}>
                      <div className="dash-bar-fill" style={{ height: `${prodMax ? Math.round((x.v / prodMax) * 100) : 0}%` }} />
                    </div>
                    <div className="dash-bar-label">{fmtDayLabel(x.day)}</div>
                    <div className="dash-bar-value">{x.v}</div>
                  </div>
                ))}
              </div>
            </div>

            <div className="card dash-card">
              <div className="dash-card-head">
                <div>
                  <div className="dash-card-title">Top stations (7 days)</div>
                  <div className="muted">Total IN+OUT punches</div>
                </div>
                <Link to="/org" className="btn btn-secondary btn-sm">
                  Manage org
                </Link>
              </div>
              {topStations.length ? (
                <div className="dash-station-list">
                  {topStations.map((s) => (
                    <div key={s.id} className="dash-station-row">
                      <div className="dash-station-name">
                        <div className="dash-station-strong">{s.name}</div>
                        <div className="muted">{s.code}</div>
                      </div>
                      <div className="dash-station-metrics">
                        <span className="pill">IN {s.inCount}</span>
                        <span className="pill">OUT {s.outCount}</span>
                        <span className="pill pill-strong">{s.total}</span>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="muted">No station activity in this range.</div>
              )}
            </div>
          </div>
        )}

        <div>
          <hr className="section-divider" />
          <h2 className="section-title">Shortcuts</h2>
          <div className="link-chips">
            <Link to="/attendance" className="link-chip">
              Attendance
            </Link>
            <Link to="/reports" className="link-chip">
              Reports
            </Link>
            <Link to="/support" className="link-chip">
              Support
            </Link>
            {(shortcutPlatform || shortcutPerms.includes("PLATFORM_COMPANY_READ")) && (
              <Link to="/platform/companies" className="link-chip">
                Companies
              </Link>
            )}
            {(shortcutPlatform || shortcutPerms.includes("PLATFORM_USER_READ")) && (
              <Link to="/platform/users" className="link-chip">
                Users
              </Link>
            )}
          </div>
        </div>
      </div>
    </Layout>
  );
}
