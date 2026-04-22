import { useEffect, useMemo, useState } from "react";
import { Layout } from "../components/Layout";
import { useAuth } from "../../auth/AuthContext";
import { companyAttendanceList, companyAttendancePunch } from "../../lib/amsApi";

type Row = {
  id: string;
  ams_staff_id: string;
  ams_station_id: string | null;
  ams_geofence_id?: string | null;
  geofence_name?: string | null;
  punch_type: string;
  punch_at: string;
  within_geofence: boolean | null;
  face_match_score: number | null;
};

function todayYmdLocal(): string {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export function AttendancePage() {
  const { state } = useAuth();
  const perms: string[] = state.me?.permissions ?? [];
  const isPlatform = state.me?.user?.is_platform_super_admin === true;
  const roles: { role_code?: string }[] = state.me?.roles ?? [];
  const mappedStaffId: string | null = state.me?.mappedStaffId ?? null;
  const isStaffPunchScoped =
    !isPlatform &&
    !perms.includes("COMPANY_ATTENDANCE_WRITE") &&
    perms.includes("COMPANY_ATTENDANCE_PUNCH") &&
    roles.some((r) => r.role_code === "STAFF");

  const canPunch =
    isPlatform ||
    perms.includes("COMPANY_ATTENDANCE_WRITE") ||
    perms.includes("COMPANY_ATTENDANCE_PUNCH");

  const [items, setItems] = useState<Row[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [pageSize] = useState(50);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const [stations, setStations] = useState<any[]>([]);
  const [staff, setStaff] = useState<any[]>([]);

  const [stationId, setStationId] = useState<string>("");
  const [staffId, setStaffId] = useState<string>("");
  const [date, setDate] = useState<string>(() => todayYmdLocal());

  const [recordStaffId, setRecordStaffId] = useState("");
  const [recordStationId, setRecordStationId] = useState("");
  const [recordPunchType, setRecordPunchType] = useState<"in" | "out" | "break_in" | "break_out">("in");
  const [punchBusy, setPunchBusy] = useState(false);
  const [punchMsg, setPunchMsg] = useState<string | null>(null);

  const pageCount = useMemo(() => Math.max(1, Math.ceil(total / pageSize)), [total, pageSize]);

  async function load(includeMeta = false) {
    if (!state.accessToken) return;
    setLoading(true);
    setError(null);
    try {
      const res = await companyAttendanceList(state.accessToken, {
        page,
        pageSize,
        stationId: stationId || undefined,
        staffId: staffId || undefined,
        date: date || undefined,
        includeMeta
      });
      setItems(res.items ?? []);
      setTotal(res.total ?? 0);
      if (includeMeta) {
        setStations(res.meta?.stations ?? []);
        setStaff(res.meta?.staff ?? []);
      }
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "load_failed");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    load(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page]);

  useEffect(() => {
    if (isStaffPunchScoped && mappedStaffId) setRecordStaffId(mappedStaffId);
  }, [isStaffPunchScoped, mappedStaffId]);

  function staffLabel(id: string) {
    const s = staff.find((x) => x.id === id);
    return s ? `${s.full_name} (${s.staff_code})` : id;
  }

  function stationLabel(id: string | null) {
    if (!id) return "";
    const s = stations.find((x) => x.id === id);
    return s ? `${s.name} (${s.code})` : id;
  }

  return (
    <Layout>
      <div className="page-stack">
        <div className="page-head">
          <div className="page-head-text">
            <h1 className="page-title">Attendance</h1>
            <p className="page-subtitle">Latest punches for the selected company</p>
          </div>
          <div className="page-actions">
            <button type="button" className="btn btn-secondary" onClick={() => load(false)} disabled={loading}>
              Refresh
            </button>
          </div>
        </div>

        {canPunch && (
          <div className="card card-elevated">
            <h2 className="section-title mt-0">Record punch</h2>
            {isStaffPunchScoped && !mappedStaffId && (
              <div className="alert alert-error" style={{ marginBottom: "var(--space-3)" }}>
                Your login is not linked to a staff profile. Ask a company admin to link your user to a staff record on
                the Staff page before you can punch.
              </div>
            )}
            {isStaffPunchScoped && mappedStaffId && (
              <p className="muted" style={{ marginBottom: "var(--space-3)" }}>
                Recording punches as <strong>{staffLabel(mappedStaffId)}</strong> (linked staff profile).
              </p>
            )}
            <div className="form-grid-punch">
              <div className="field">
                <span className="field-label">Staff</span>
                {isStaffPunchScoped && mappedStaffId ? (
                  <select className="select" value={recordStaffId} disabled>
                    <option value={mappedStaffId}>{staffLabel(mappedStaffId)}</option>
                  </select>
                ) : (
                  <select className="select" value={recordStaffId} onChange={(e) => setRecordStaffId(e.target.value)}>
                    <option value="">Select staff…</option>
                    {staff.map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.full_name} ({s.staff_code})
                      </option>
                    ))}
                  </select>
                )}
              </div>
              <div className="field">
                <span className="field-label">Station (optional)</span>
                <select className="select" value={recordStationId} onChange={(e) => setRecordStationId(e.target.value)}>
                  <option value="">—</option>
                  {stations.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.name} ({s.code})
                    </option>
                  ))}
                </select>
              </div>
              <div className="field">
                <span className="field-label">Type</span>
                <select
                  className="select"
                  value={recordPunchType}
                  onChange={(e) => setRecordPunchType(e.target.value as typeof recordPunchType)}
                >
                  <option value="in">in</option>
                  <option value="out">out</option>
                  <option value="break_in">break_in</option>
                  <option value="break_out">break_out</option>
                </select>
              </div>
              <button
                type="button"
                className="btn btn-primary"
                disabled={punchBusy || !recordStaffId || (isStaffPunchScoped && !mappedStaffId)}
                onClick={async () => {
                  if (!state.accessToken || !recordStaffId) return;
                  setPunchBusy(true);
                  setPunchMsg(null);
                  setError(null);
                  try {
                    await companyAttendancePunch(state.accessToken, {
                      staffId: recordStaffId,
                      punchType: recordPunchType,
                      stationId: recordStationId || undefined
                    });
                    setPunchMsg("Punch saved.");
                    await load(false);
                  } catch (e: unknown) {
                    setError(e instanceof Error ? e.message : "punch_failed");
                  } finally {
                    setPunchBusy(false);
                  }
                }}
              >
                {punchBusy ? "Saving…" : "Save punch"}
              </button>
            </div>
            {punchMsg && <div className="alert alert-success mt-3">{punchMsg}</div>}
          </div>
        )}

        <div className="filters-row">
          <select className="select" value={stationId} onChange={(e) => setStationId(e.target.value)}>
            <option value="">All stations</option>
            {stations.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name} ({s.code})
              </option>
            ))}
          </select>
          <select className="select" value={staffId} onChange={(e) => setStaffId(e.target.value)}>
            <option value="">All staff</option>
            {staff.map((s) => (
              <option key={s.id} value={s.id}>
                {s.full_name} ({s.staff_code})
              </option>
            ))}
          </select>
          <input
            className="input input-date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            type="date"
          />
          <button
            type="button"
            className="btn btn-primary"
            onClick={() => {
              setPage(1);
              load(false);
            }}
          >
            Apply filters
          </button>
        </div>

        {error && <div className="alert alert-error">{error}</div>}

        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Punch at</th>
                <th>Type</th>
                <th>Staff</th>
                <th>Station</th>
                <th>Geofence</th>
                <th>Face score</th>
              </tr>
            </thead>
            <tbody>
              {items.map((r) => (
                <tr key={r.id}>
                  <td>{new Date(r.punch_at).toLocaleString()}</td>
                  <td className="cell-strong">{r.punch_type}</td>
                  <td>{staffLabel(r.ams_staff_id)}</td>
                  <td>{stationLabel(r.ams_station_id)}</td>
                  <td className="cell-muted">
                    {r.geofence_name
                      ? `${r.geofence_name} · ${r.within_geofence == null ? "—" : r.within_geofence ? "Within" : "Outside"}`
                      : r.within_geofence == null
                        ? "—"
                        : r.within_geofence
                          ? "Within"
                          : "Outside"}
                  </td>
                  <td className="cell-muted">
                    {r.face_match_score == null ? "—" : r.face_match_score.toFixed(3)}
                  </td>
                </tr>
              ))}
              {items.length === 0 && (
                <tr>
                  <td colSpan={6} className="cell-muted" style={{ padding: "var(--space-4)" }}>
                    {loading ? "Loading…" : "No attendance logs"}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        <div className="pagination">
          <span className="muted">
            Page {page} / {pageCount} · Total {total}
          </span>
          <div className="toolbar">
            <button type="button" className="btn btn-secondary btn-sm" disabled={page <= 1} onClick={() => setPage((p) => Math.max(1, p - 1))}>
              Previous
            </button>
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              disabled={page >= pageCount}
              onClick={() => setPage((p) => Math.min(pageCount, p + 1))}
            >
              Next
            </button>
          </div>
        </div>
      </div>
    </Layout>
  );
}
