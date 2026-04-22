import { useEffect, useMemo, useState } from "react";
import { Layout } from "../components/Layout";
import { useAuth } from "../../auth/AuthContext";
import { companyOrgCreate, companyOrgList, companyOrgUpdate } from "../../lib/amsApi";
import { Pagination } from "../components/Pagination";

type Tab = "zones" | "branches" | "stations" | "geofences";

type ZoneForm = {
  code: string;
  name: string;
  description: string;
  isActive: boolean;
};

type BranchForm = {
  code: string;
  name: string;
  zoneId: string;
  isActive: boolean;
};

type ZoneOption = { id: string; code: string; name: string };

type BranchOption = { id: string; code: string; name: string; zoneId: string };

type StationForm = {
  code: string;
  name: string;
  zoneId: string;
  branchId: string;
  isActive: boolean;
};

type StationOption = { id: string; code: string; name: string };

type GeofenceForm = {
  code: string;
  name: string;
  stationId: string;
  geofenceType: string;
  centerLat: string;
  centerLng: string;
  radiusM: string;
  isActive: boolean;
};

export function OrgPage() {
  const { state } = useAuth();
  const [tab, setTab] = useState<Tab>("zones");
  const [items, setItems] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(25);
  const [q, setQ] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const [zoneModalOpen, setZoneModalOpen] = useState(false);
  const [zoneEditingId, setZoneEditingId] = useState<string | null>(null);
  const [zoneForm, setZoneForm] = useState<ZoneForm>({ code: "", name: "", description: "", isActive: true });
  const [zoneSaving, setZoneSaving] = useState(false);

  const [branchModalOpen, setBranchModalOpen] = useState(false);
  const [branchEditingId, setBranchEditingId] = useState<string | null>(null);
  const [branchForm, setBranchForm] = useState<BranchForm>({ code: "", name: "", zoneId: "", isActive: true });
  const [branchSaving, setBranchSaving] = useState(false);
  const [zoneOptions, setZoneOptions] = useState<ZoneOption[]>([]);
  const [branchOptions, setBranchOptions] = useState<BranchOption[]>([]);

  const [stationModalOpen, setStationModalOpen] = useState(false);
  const [stationEditingId, setStationEditingId] = useState<string | null>(null);
  const [stationForm, setStationForm] = useState<StationForm>({ code: "", name: "", zoneId: "", branchId: "", isActive: true });
  const [stationSaving, setStationSaving] = useState(false);

  const [stationOptions, setStationOptions] = useState<StationOption[]>([]);

  const [geofenceModalOpen, setGeofenceModalOpen] = useState(false);
  const [geofenceEditingId, setGeofenceEditingId] = useState<string | null>(null);
  const [geofenceForm, setGeofenceForm] = useState<GeofenceForm>({
    code: "",
    name: "",
    stationId: "",
    geofenceType: "circle",
    centerLat: "",
    centerLng: "",
    radiusM: "100",
    isActive: true
  });
  const [geofenceSaving, setGeofenceSaving] = useState(false);

  const pageCount = useMemo(() => Math.max(1, Math.ceil(total / pageSize)), [total, pageSize]);

  const branchesForStation = useMemo(() => {
    if (!stationForm.zoneId) return branchOptions;
    return branchOptions.filter((b) => b.zoneId === stationForm.zoneId);
  }, [branchOptions, stationForm.zoneId]);

  async function load() {
    if (!state.accessToken) return;
    setLoading(true);
    setError(null);
    try {
      const res = await companyOrgList(state.accessToken, tab, { page, pageSize, q: q.trim() || undefined });
      setItems(res.items ?? []);
      setTotal(res.total ?? 0);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "load_failed");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    setPage(1);
  }, [tab]);

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab, page, pageSize]);

  function columnsFor(t: Tab) {
    if (t === "zones") return ["code", "name", "description", "is_active"];
    if (t === "branches") return ["code", "name", "ams_zone_id", "is_active"];
    if (t === "stations") return ["code", "name", "ams_zone_id", "ams_branch_id", "is_active"];
    return ["code", "name", "ams_station_id", "geofence_type", "is_active"];
  }

  async function loadZoneOptions() {
    if (!state.accessToken) return;
    const res = await companyOrgList(state.accessToken, "zones", { page: 1, pageSize: 100 });
    setZoneOptions(
      (res.items ?? []).map((z: any) => ({
        id: String(z.id),
        code: String(z.code ?? ""),
        name: String(z.name ?? "")
      }))
    );
  }

  async function loadBranchOptions() {
    if (!state.accessToken) return;
    const res = await companyOrgList(state.accessToken, "branches", { page: 1, pageSize: 200 });
    setBranchOptions(
      (res.items ?? []).map((b: any) => ({
        id: String(b.id),
        code: String(b.code ?? ""),
        name: String(b.name ?? ""),
        zoneId: b.ams_zone_id != null ? String(b.ams_zone_id) : ""
      }))
    );
  }

  async function loadStationOptions() {
    if (!state.accessToken) return;
    const res = await companyOrgList(state.accessToken, "stations", { page: 1, pageSize: 200 });
    setStationOptions(
      (res.items ?? []).map((s: any) => ({
        id: String(s.id),
        code: String(s.code ?? ""),
        name: String(s.name ?? "")
      }))
    );
  }

  function openCreateForCurrentTab() {
    if (tab === "zones") {
      setZoneEditingId(null);
      setZoneForm({ code: "", name: "", description: "", isActive: true });
      setZoneModalOpen(true);
      return;
    }
    if (tab === "branches") {
      void (async () => {
        try {
          await loadZoneOptions();
        } catch (e: unknown) {
          setError(e instanceof Error ? e.message : "load_zones_failed");
        }
      })();
      setBranchEditingId(null);
      setBranchForm({ code: "", name: "", zoneId: "", isActive: true });
      setBranchModalOpen(true);
      return;
    }
    if (tab === "stations") {
      void (async () => {
        try {
          await Promise.all([loadZoneOptions(), loadBranchOptions()]);
        } catch (e: unknown) {
          setError(e instanceof Error ? e.message : "load_org_meta_failed");
        }
      })();
      setStationEditingId(null);
      setStationForm({ code: "", name: "", zoneId: "", branchId: "", isActive: true });
      setStationModalOpen(true);
      return;
    }
    if (tab === "geofences") {
      void (async () => {
        try {
          await loadStationOptions();
        } catch (e: unknown) {
          setError(e instanceof Error ? e.message : "load_stations_failed");
        }
      })();
      setGeofenceEditingId(null);
      setGeofenceForm({
        code: "",
        name: "",
        stationId: "",
        geofenceType: "circle",
        centerLat: "",
        centerLng: "",
        radiusM: "100",
        isActive: true
      });
      setGeofenceModalOpen(true);
      return;
    }
  }

  async function saveZone() {
    if (!state.accessToken) return;
    setZoneSaving(true);
    setError(null);
    try {
      if (!zoneEditingId) {
        await companyOrgCreate(state.accessToken, "zones", {
          code: zoneForm.code.trim(),
          name: zoneForm.name.trim(),
          description: zoneForm.description.trim()
        });
      } else {
        await companyOrgUpdate(state.accessToken, "zones", {
          id: zoneEditingId,
          name: zoneForm.name.trim(),
          description: zoneForm.description.trim(),
          isActive: zoneForm.isActive
        });
      }
      setZoneModalOpen(false);
      await load();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "save_failed");
    } finally {
      setZoneSaving(false);
    }
  }

  function openEditZone(row: any) {
    setZoneEditingId(String(row.id));
    setZoneForm({
      code: String(row.code ?? ""),
      name: String(row.name ?? ""),
      description: String(row.description ?? ""),
      isActive: Boolean(row.is_active)
    });
    setZoneModalOpen(true);
  }

  function openEditBranch(row: any) {
    void (async () => {
      try {
        await loadZoneOptions();
      } catch (e: unknown) {
        setError(e instanceof Error ? e.message : "load_zones_failed");
      }
    })();
    setBranchEditingId(String(row.id));
    setBranchForm({
      code: String(row.code ?? ""),
      name: String(row.name ?? ""),
      zoneId: row.ams_zone_id != null ? String(row.ams_zone_id) : "",
      isActive: Boolean(row.is_active)
    });
    setBranchModalOpen(true);
  }

  function openEditStation(row: any) {
    void (async () => {
      try {
        await Promise.all([loadZoneOptions(), loadBranchOptions()]);
      } catch (e: unknown) {
        setError(e instanceof Error ? e.message : "load_org_meta_failed");
      }
    })();
    setStationEditingId(String(row.id));
    setStationForm({
      code: String(row.code ?? ""),
      name: String(row.name ?? ""),
      zoneId: row.ams_zone_id != null ? String(row.ams_zone_id) : "",
      branchId: row.ams_branch_id != null ? String(row.ams_branch_id) : "",
      isActive: Boolean(row.is_active)
    });
    setStationModalOpen(true);
  }

  function openEditGeofence(row: any) {
    void (async () => {
      try {
        await loadStationOptions();
      } catch (e: unknown) {
        setError(e instanceof Error ? e.message : "load_stations_failed");
      }
    })();
    setGeofenceEditingId(String(row.id));
    const lat = row.center_lat;
    const lng = row.center_lng;
    const rad = row.radius_m;
    setGeofenceForm({
      code: String(row.code ?? ""),
      name: String(row.name ?? ""),
      stationId: row.ams_station_id != null ? String(row.ams_station_id) : "",
      geofenceType: String(row.geofence_type ?? "circle"),
      centerLat: lat != null && lat !== "" ? String(lat) : "",
      centerLng: lng != null && lng !== "" ? String(lng) : "",
      radiusM: rad != null && rad !== "" ? String(rad) : "100",
      isActive: Boolean(row.is_active)
    });
    setGeofenceModalOpen(true);
  }

  function parseGeofenceNumber(s: string): number | null {
    const t = s.trim();
    if (!t) return null;
    const n = Number(t);
    return Number.isFinite(n) ? n : null;
  }

  async function saveGeofence() {
    if (!state.accessToken) return;
    setGeofenceSaving(true);
    setError(null);
    try {
      const stationId = geofenceForm.stationId.trim() ? geofenceForm.stationId.trim() : null;
      const centerLat = parseGeofenceNumber(geofenceForm.centerLat);
      const centerLng = parseGeofenceNumber(geofenceForm.centerLng);
      const radiusM = parseGeofenceNumber(geofenceForm.radiusM);
      if (!geofenceEditingId) {
        await companyOrgCreate(state.accessToken, "geofences", {
          code: geofenceForm.code.trim(),
          name: geofenceForm.name.trim(),
          stationId,
          geofenceType: geofenceForm.geofenceType || "circle",
          centerLat,
          centerLng,
          radiusM,
          polygonJson: []
        });
      } else {
        await companyOrgUpdate(state.accessToken, "geofences", {
          id: geofenceEditingId,
          name: geofenceForm.name.trim(),
          stationId,
          isActive: geofenceForm.isActive,
          centerLat,
          centerLng,
          radiusM
        });
      }
      setGeofenceModalOpen(false);
      await load();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "save_failed");
    } finally {
      setGeofenceSaving(false);
    }
  }

  async function saveStation() {
    if (!state.accessToken) return;
    setStationSaving(true);
    setError(null);
    try {
      const zoneId = stationForm.zoneId.trim() ? stationForm.zoneId.trim() : null;
      const branchId = stationForm.branchId.trim() ? stationForm.branchId.trim() : null;
      if (!stationEditingId) {
        await companyOrgCreate(state.accessToken, "stations", {
          code: stationForm.code.trim(),
          name: stationForm.name.trim(),
          zoneId,
          branchId
        });
      } else {
        await companyOrgUpdate(state.accessToken, "stations", {
          id: stationEditingId,
          name: stationForm.name.trim(),
          zoneId,
          branchId,
          isActive: stationForm.isActive
        });
      }
      setStationModalOpen(false);
      await load();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "save_failed");
    } finally {
      setStationSaving(false);
    }
  }

  async function saveBranch() {
    if (!state.accessToken) return;
    setBranchSaving(true);
    setError(null);
    try {
      const zoneId = branchForm.zoneId.trim() ? branchForm.zoneId.trim() : null;
      if (!branchEditingId) {
        await companyOrgCreate(state.accessToken, "branches", {
          code: branchForm.code.trim(),
          name: branchForm.name.trim(),
          zoneId
        });
      } else {
        await companyOrgUpdate(state.accessToken, "branches", {
          id: branchEditingId,
          name: branchForm.name.trim(),
          zoneId,
          isActive: branchForm.isActive
        });
      }
      setBranchModalOpen(false);
      await load();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "save_failed");
    } finally {
      setBranchSaving(false);
    }
  }

  async function toggleActive(row: any) {
    try {
      await companyOrgUpdate(state.accessToken!, tab, { id: row.id, isActive: !row.is_active });
      await load();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "update_failed");
    }
  }

  async function rename(row: any) {
    if (tab === "zones") {
      openEditZone(row);
      return;
    }
    if (tab === "branches") {
      openEditBranch(row);
      return;
    }
    if (tab === "stations") {
      openEditStation(row);
      return;
    }
    if (tab === "geofences") {
      openEditGeofence(row);
      return;
    }
    const name = prompt("Name", row.name);
    if (!name) return;
    try {
      await companyOrgUpdate(state.accessToken!, tab, { id: row.id, name });
      await load();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "update_failed");
    }
  }

  return (
    <Layout>
      <div className="page-stack">
        <div className="page-head">
          <div className="page-head-text">
            <h1 className="page-title">Organization</h1>
            <p className="page-subtitle">Zones, branches, stations, and geofences</p>
          </div>
          <div className="page-actions">
            <button type="button" className="btn btn-primary" onClick={openCreateForCurrentTab}>
              New record
            </button>
          </div>
        </div>

        <div className="tabs">
          {(["zones", "branches", "stations", "geofences"] as Tab[]).map((t) => (
            <button key={t} type="button" className={`tab${tab === t ? " is-active" : ""}`} onClick={() => setTab(t)}>
              {t}
            </button>
          ))}
        </div>

        <div className="toolbar">
          <input className="input toolbar-grow" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search by code or name" />
          <button
            type="button"
            className="btn btn-secondary"
            onClick={() => {
              setPage(1);
              load();
            }}
          >
            Search
          </button>
          <button
            type="button"
            className="btn btn-ghost"
            onClick={() => {
              setQ("");
              setPage(1);
              load();
            }}
          >
            Reset
          </button>
        </div>

        {error && <div className="alert alert-error">{error}</div>}

        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                {columnsFor(tab).map((c) => (
                  <th key={c}>{c}</th>
                ))}
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {items.map((r) => (
                <tr key={r.id}>
                  {columnsFor(tab).map((c) => (
                    <td key={c}>{String((r as any)[c] ?? "")}</td>
                  ))}
                  <td>
                    <div className="table-actions">
                      <button type="button" className="btn btn-ghost btn-sm" onClick={() => rename(r)}>
                        {tab === "zones" || tab === "branches" || tab === "stations" || tab === "geofences" ? "Edit" : "Rename"}
                      </button>
                      <button type="button" className="btn btn-secondary btn-sm" onClick={() => toggleActive(r)}>
                        {r.is_active ? "Deactivate" : "Activate"}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {items.length === 0 && (
                <tr>
                  <td colSpan={columnsFor(tab).length + 1} className="cell-muted" style={{ padding: "var(--space-4)" }}>
                    {loading ? "Loading…" : "No records"}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        <Pagination
          page={page}
          pageSize={pageSize}
          total={total}
          onPageChange={(p) => setPage(p)}
          onPageSizeChange={(n) => {
            setPage(1);
            setPageSize(n);
          }}
          pageSizeOptions={[10, 25, 50, 100]}
        />
      </div>

      {zoneModalOpen && (
        <div className="modal-backdrop" role="presentation" onMouseDown={() => !zoneSaving && setZoneModalOpen(false)}>
          <div className="modal-card" role="dialog" aria-modal="true" onMouseDown={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <div>
                <h2 className="modal-title">{zoneEditingId ? "Edit zone" : "Add zone"}</h2>
                <p className="muted" style={{ margin: "0.35rem 0 0" }}>
                  Codes are unique per company. Zone code cannot be changed after creation.
                </p>
              </div>
              <button type="button" className="btn btn-ghost btn-sm" disabled={zoneSaving} onClick={() => setZoneModalOpen(false)}>
                Close
              </button>
            </div>

            <div className="form-grid">
                <div className="field">
                  <label className="field-label" htmlFor="zone-code">
                    Code
                  </label>
                  <input
                    id="zone-code"
                    className="input"
                    value={zoneForm.code}
                    disabled={Boolean(zoneEditingId)}
                    onChange={(e) => setZoneForm((s) => ({ ...s, code: e.target.value }))}
                  />
                </div>

                <div className="field">
                  <label className="field-label" htmlFor="zone-name">
                    Name
                  </label>
                  <input id="zone-name" className="input" value={zoneForm.name} onChange={(e) => setZoneForm((s) => ({ ...s, name: e.target.value }))} />
                </div>

                <div className="field">
                  <label className="field-label" htmlFor="zone-desc">
                    Description
                  </label>
                  <textarea
                    id="zone-desc"
                    className="input"
                    rows={4}
                    value={zoneForm.description}
                    onChange={(e) => setZoneForm((s) => ({ ...s, description: e.target.value }))}
                  />
                </div>

                {zoneEditingId && (
                  <label className="checkbox-row">
                    <input type="checkbox" checked={zoneForm.isActive} onChange={(e) => setZoneForm((s) => ({ ...s, isActive: e.target.checked }))} />
                    <span>Active</span>
                  </label>
                )}
            </div>

            <div className="toolbar" style={{ marginTop: "var(--space-4)", justifyContent: "flex-end" }}>
              <button type="button" className="btn btn-ghost" disabled={zoneSaving} onClick={() => setZoneModalOpen(false)}>
                Cancel
              </button>
              <button
                type="button"
                className="btn btn-primary"
                disabled={zoneSaving || zoneForm.code.trim().length < 2 || zoneForm.name.trim().length < 2}
                onClick={() => void saveZone()}
              >
                {zoneSaving ? "Saving…" : zoneEditingId ? "Save changes" : "Create zone"}
              </button>
            </div>
          </div>
        </div>
      )}

      {branchModalOpen && (
        <div className="modal-backdrop" role="presentation" onMouseDown={() => !branchSaving && setBranchModalOpen(false)}>
          <div className="modal-card" role="dialog" aria-modal="true" onMouseDown={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <div>
                <h2 className="modal-title">{branchEditingId ? "Edit branch" : "Add branch"}</h2>
                <p className="muted" style={{ margin: "0.35rem 0 0" }}>
                  Branch code cannot be changed after creation. Parent zone can be updated when editing.
                </p>
              </div>
              <button type="button" className="btn btn-ghost btn-sm" disabled={branchSaving} onClick={() => setBranchModalOpen(false)}>
                Close
              </button>
            </div>

            <div className="form-grid">
              <div className="field">
                <label className="field-label" htmlFor="branch-code">
                  Code
                </label>
                <input
                  id="branch-code"
                  className="input"
                  value={branchForm.code}
                  disabled={Boolean(branchEditingId)}
                  onChange={(e) => setBranchForm((s) => ({ ...s, code: e.target.value }))}
                />
              </div>

              <div className="field">
                <label className="field-label" htmlFor="branch-name">
                  Name
                </label>
                <input id="branch-name" className="input" value={branchForm.name} onChange={(e) => setBranchForm((s) => ({ ...s, name: e.target.value }))} />
              </div>

              <div className="field">
                <label className="field-label" htmlFor="branch-zone">
                  Zone
                </label>
                <select
                  id="branch-zone"
                  className="input"
                  value={branchForm.zoneId}
                  onChange={(e) => setBranchForm((s) => ({ ...s, zoneId: e.target.value }))}
                >
                  {(!branchEditingId || branchForm.zoneId === "") && <option value="">— None —</option>}
                  {zoneOptions.map((z) => (
                    <option key={z.id} value={z.id}>
                      {z.code} — {z.name}
                    </option>
                  ))}
                </select>
              </div>

              {branchEditingId && (
                <label className="checkbox-row">
                  <input type="checkbox" checked={branchForm.isActive} onChange={(e) => setBranchForm((s) => ({ ...s, isActive: e.target.checked }))} />
                  <span>Active</span>
                </label>
              )}
            </div>

            <div className="toolbar" style={{ marginTop: "var(--space-4)", justifyContent: "flex-end" }}>
              <button type="button" className="btn btn-ghost" disabled={branchSaving} onClick={() => setBranchModalOpen(false)}>
                Cancel
              </button>
              <button
                type="button"
                className="btn btn-primary"
                disabled={
                  branchSaving ||
                  branchForm.name.trim().length < 2 ||
                  (!branchEditingId && branchForm.code.trim().length < 2)
                }
                onClick={() => void saveBranch()}
              >
                {branchSaving ? "Saving…" : branchEditingId ? "Save changes" : "Create branch"}
              </button>
            </div>
          </div>
        </div>
      )}

      {stationModalOpen && (
        <div className="modal-backdrop" role="presentation" onMouseDown={() => !stationSaving && setStationModalOpen(false)}>
          <div className="modal-card" role="dialog" aria-modal="true" onMouseDown={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <div>
                <h2 className="modal-title">{stationEditingId ? "Edit station" : "Add station"}</h2>
                <p className="muted" style={{ margin: "0.35rem 0 0" }}>
                  Station code cannot be changed after creation. Zone and branch can be updated when editing.
                </p>
              </div>
              <button type="button" className="btn btn-ghost btn-sm" disabled={stationSaving} onClick={() => setStationModalOpen(false)}>
                Close
              </button>
            </div>

            <div className="form-grid">
              <div className="field">
                <label className="field-label" htmlFor="station-code">
                  Code
                </label>
                <input
                  id="station-code"
                  className="input"
                  value={stationForm.code}
                  disabled={Boolean(stationEditingId)}
                  onChange={(e) => setStationForm((s) => ({ ...s, code: e.target.value }))}
                />
              </div>

              <div className="field">
                <label className="field-label" htmlFor="station-name">
                  Name
                </label>
                <input id="station-name" className="input" value={stationForm.name} onChange={(e) => setStationForm((s) => ({ ...s, name: e.target.value }))} />
              </div>

              <div className="field">
                <label className="field-label" htmlFor="station-zone">
                  Zone
                </label>
                <select
                  id="station-zone"
                  className="input"
                  value={stationForm.zoneId}
                  onChange={(e) => {
                    const z = e.target.value;
                    setStationForm((s) => {
                      const next = { ...s, zoneId: z };
                      if (z && s.branchId) {
                        const br = branchOptions.find((b) => b.id === s.branchId);
                        if (!br || br.zoneId !== z) next.branchId = "";
                      }
                      return next;
                    });
                  }}
                >
                  {(!stationEditingId || stationForm.zoneId === "") && <option value="">— None —</option>}
                  {zoneOptions.map((z) => (
                    <option key={z.id} value={z.id}>
                      {z.code} — {z.name}
                    </option>
                  ))}
                </select>
              </div>

              <div className="field">
                <label className="field-label" htmlFor="station-branch">
                  Branch
                </label>
                <select
                  id="station-branch"
                  className="input"
                  value={stationForm.branchId}
                  onChange={(e) => setStationForm((s) => ({ ...s, branchId: e.target.value }))}
                >
                  {(!stationEditingId || stationForm.branchId === "") && <option value="">— None —</option>}
                  {branchesForStation.map((b) => (
                    <option key={b.id} value={b.id}>
                      {b.code} — {b.name}
                    </option>
                  ))}
                </select>
              </div>

              {stationEditingId && (
                <label className="checkbox-row">
                  <input type="checkbox" checked={stationForm.isActive} onChange={(e) => setStationForm((s) => ({ ...s, isActive: e.target.checked }))} />
                  <span>Active</span>
                </label>
              )}
            </div>

            <div className="toolbar" style={{ marginTop: "var(--space-4)", justifyContent: "flex-end" }}>
              <button type="button" className="btn btn-ghost" disabled={stationSaving} onClick={() => setStationModalOpen(false)}>
                Cancel
              </button>
              <button
                type="button"
                className="btn btn-primary"
                disabled={
                  stationSaving ||
                  stationForm.name.trim().length < 2 ||
                  (!stationEditingId && stationForm.code.trim().length < 2)
                }
                onClick={() => void saveStation()}
              >
                {stationSaving ? "Saving…" : stationEditingId ? "Save changes" : "Create station"}
              </button>
            </div>
          </div>
        </div>
      )}

      {geofenceModalOpen && (
        <div className="modal-backdrop" role="presentation" onMouseDown={() => !geofenceSaving && setGeofenceModalOpen(false)}>
          <div className="modal-card" role="dialog" aria-modal="true" onMouseDown={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <div>
                <h2 className="modal-title">{geofenceEditingId ? "Edit geofence" : "Add geofence"}</h2>
                <p className="muted" style={{ margin: "0.35rem 0 0" }}>
                  Code cannot be changed after creation. Circle uses center latitude/longitude (decimal degrees) and radius in meters.
                </p>
              </div>
              <button type="button" className="btn btn-ghost btn-sm" disabled={geofenceSaving} onClick={() => setGeofenceModalOpen(false)}>
                Close
              </button>
            </div>

            <div className="form-grid">
              <div className="field">
                <label className="field-label" htmlFor="gf-code">
                  Code
                </label>
                <input
                  id="gf-code"
                  className="input"
                  value={geofenceForm.code}
                  disabled={Boolean(geofenceEditingId)}
                  onChange={(e) => setGeofenceForm((s) => ({ ...s, code: e.target.value }))}
                />
              </div>

              <div className="field">
                <label className="field-label" htmlFor="gf-name">
                  Name
                </label>
                <input id="gf-name" className="input" value={geofenceForm.name} onChange={(e) => setGeofenceForm((s) => ({ ...s, name: e.target.value }))} />
              </div>

              <div className="field">
                <label className="field-label" htmlFor="gf-station">
                  Station
                </label>
                <select
                  id="gf-station"
                  className="input"
                  value={geofenceForm.stationId}
                  onChange={(e) => setGeofenceForm((s) => ({ ...s, stationId: e.target.value }))}
                >
                  {(!geofenceEditingId || geofenceForm.stationId === "") && <option value="">— None —</option>}
                  {stationOptions.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.code} — {s.name}
                    </option>
                  ))}
                </select>
              </div>

              <div className="field">
                <label className="field-label" htmlFor="gf-type">
                  Type
                </label>
                <select
                  id="gf-type"
                  className="input"
                  value={geofenceForm.geofenceType}
                  disabled={Boolean(geofenceEditingId)}
                  onChange={(e) => setGeofenceForm((s) => ({ ...s, geofenceType: e.target.value }))}
                >
                  <option value="circle">circle</option>
                </select>
              </div>

              <div className="field">
                <label className="field-label" htmlFor="gf-lat">
                  Center latitude
                </label>
                <input
                  id="gf-lat"
                  className="input"
                  inputMode="decimal"
                  placeholder="e.g. 12.9716"
                  value={geofenceForm.centerLat}
                  onChange={(e) => setGeofenceForm((s) => ({ ...s, centerLat: e.target.value }))}
                />
              </div>

              <div className="field">
                <label className="field-label" htmlFor="gf-lng">
                  Center longitude
                </label>
                <input
                  id="gf-lng"
                  className="input"
                  inputMode="decimal"
                  placeholder="e.g. 77.5946"
                  value={geofenceForm.centerLng}
                  onChange={(e) => setGeofenceForm((s) => ({ ...s, centerLng: e.target.value }))}
                />
              </div>

              <div className="field">
                <label className="field-label" htmlFor="gf-radius">
                  Radius (meters)
                </label>
                <input
                  id="gf-radius"
                  className="input"
                  inputMode="numeric"
                  value={geofenceForm.radiusM}
                  onChange={(e) => setGeofenceForm((s) => ({ ...s, radiusM: e.target.value }))}
                />
              </div>

              {geofenceEditingId && (
                <label className="checkbox-row">
                  <input type="checkbox" checked={geofenceForm.isActive} onChange={(e) => setGeofenceForm((s) => ({ ...s, isActive: e.target.checked }))} />
                  <span>Active</span>
                </label>
              )}
            </div>

            <div className="toolbar" style={{ marginTop: "var(--space-4)", justifyContent: "flex-end" }}>
              <button type="button" className="btn btn-ghost" disabled={geofenceSaving} onClick={() => setGeofenceModalOpen(false)}>
                Cancel
              </button>
              <button
                type="button"
                className="btn btn-primary"
                disabled={
                  geofenceSaving ||
                  geofenceForm.name.trim().length < 2 ||
                  (!geofenceEditingId && geofenceForm.code.trim().length < 2)
                }
                onClick={() => void saveGeofence()}
              >
                {geofenceSaving ? "Saving…" : geofenceEditingId ? "Save changes" : "Create geofence"}
              </button>
            </div>
          </div>
        </div>
      )}
    </Layout>
  );
}
