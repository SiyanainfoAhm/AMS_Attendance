import { useEffect, useMemo, useState } from "react";
import { Layout } from "../components/Layout";
import { useAuth } from "../../auth/AuthContext";
import { Pagination } from "../components/Pagination";
import {
  companyStaffAddDocument,
  companyStaffCreate,
  companyStaffList,
  companyStaffMapStation,
  companyStaffMapUser,
  companyStaffStationMapsList,
  companyStaffUserLinksList,
  companyStaffUpdate
} from "../../lib/amsApi";

type StaffRow = {
  id: string;
  staff_code: string;
  full_name: string;
  mobile: string | null;
  email: string | null;
  status: string;
  is_active: boolean;
  created_at: string;
};

type CompanyUserOption = { id: string; displayName: string | null; email: string | null };

type MappedStationItem = {
  stationId: string;
  isActive: boolean;
  isPrimary: boolean;
  updatedAt?: string | null;
  station?: { id: string; code: string; name: string } | null;
};

export function StaffPage() {
  const { state } = useAuth();
  const perms: string[] = state.me?.permissions ?? [];
  const isPlatform = state.me?.user?.is_platform_super_admin === true;
  const canMapUser = isPlatform || perms.includes("COMPANY_STAFF_WRITE");
  const [items, setItems] = useState<StaffRow[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(25);
  const [q, setQ] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const [stations, setStations] = useState<any[]>([]);
  const [companyUsers, setCompanyUsers] = useState<CompanyUserOption[]>([]);

  const pageCount = useMemo(() => Math.max(1, Math.ceil(total / pageSize)), [total, pageSize]);

  async function load(includeMeta = false) {
    if (!state.accessToken) return;
    setLoading(true);
    setError(null);
    try {
      const res = await companyStaffList(state.accessToken, { page, pageSize, q: q.trim() || undefined, includeMeta });
      setItems(res.items ?? []);
      setTotal(res.total ?? 0);
      if (includeMeta) {
        setStations(res.meta?.stations ?? []);
        setCompanyUsers(res.meta?.users ?? []);
      }
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "load_failed");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (!state.accessToken) return;
    load(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.accessToken]);

  useEffect(() => {
    if (!state.accessToken) return;
    load(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.accessToken, page, pageSize]);

  const [createOpen, setCreateOpen] = useState(false);
  const [sc, setSc] = useState("");
  const [fn, setFn] = useState("");
  const [mb, setMb] = useState("");
  const [em, setEm] = useState("");

  const [editOpen, setEditOpen] = useState<null | { staffId: string; label: string; staffCode: string }>(null);
  const [editFn, setEditFn] = useState("");
  const [editMb, setEditMb] = useState("");
  const [editEm, setEditEm] = useState("");
  const [editStatus, setEditStatus] = useState("active");
  const [editSaving, setEditSaving] = useState(false);

  const [mapOpen, setMapOpen] = useState<null | { staffId: string; label: string }>(null);
  const [stationId, setStationId] = useState("");
  const [mappedStations, setMappedStations] = useState<MappedStationItem[]>([]);
  const [mapLoading, setMapLoading] = useState(false);
  const [mapBusy, setMapBusy] = useState(false);

  const [linkOpen, setLinkOpen] = useState<null | { staffId: string; label: string }>(null);
  const [linkUserOptionId, setLinkUserOptionId] = useState("");
  const [linkBusy, setLinkBusy] = useState(false);
  const [linkLoading, setLinkLoading] = useState(false);
  const [linkedUsers, setLinkedUsers] = useState<any[]>([]);

  const [docOpen, setDocOpen] = useState<null | { staffId: string; label: string }>(null);
  const [docType, setDocType] = useState("ID");
  const [docNo, setDocNo] = useState("");
  const [bucket, setBucket] = useState("staff-documents");
  const [path, setPath] = useState("");

  return (
    <Layout>
      <div className="page-stack">
        <div className="page-head">
          <div className="page-head-text">
            <h1 className="page-title">Staff</h1>
            <p className="page-subtitle">Company directory and onboarding</p>
          </div>
          <div className="page-actions">
            <button type="button" className="btn btn-primary" onClick={() => setCreateOpen(true)}>
              New staff
            </button>
          </div>
        </div>

        <div className="toolbar">
          <input
            className="input toolbar-grow"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search by code, name, or mobile"
          />
          <button
            type="button"
            className="btn btn-secondary"
            onClick={() => {
              setPage(1);
              load(false);
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
              load(false);
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
                <th>Code</th>
                <th>Name</th>
                <th>Mobile</th>
                <th>Status</th>
                <th>Active</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {items.map((s) => (
                <tr key={s.id}>
                  <td className="cell-strong">{s.staff_code}</td>
                  <td>{s.full_name}</td>
                  <td className="cell-muted">{s.mobile ?? "—"}</td>
                  <td>{s.status}</td>
                  <td>{s.is_active ? "Yes" : "No"}</td>
                  <td>
                    <div className="table-actions">
                      <button
                        type="button"
                        className="btn btn-ghost btn-sm"
                        onClick={() => {
                          setEditOpen({ staffId: s.id, label: `${s.full_name} (${s.staff_code})`, staffCode: s.staff_code });
                          setEditFn(s.full_name ?? "");
                          setEditMb(s.mobile ?? "");
                          setEditEm(s.email ?? "");
                          setEditStatus(s.status ?? "active");
                        }}
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        className="btn btn-secondary btn-sm"
                        onClick={async () => {
                          try {
                            await companyStaffUpdate(state.accessToken!, { staffId: s.id, isActive: !s.is_active });
                            await load(false);
                          } catch (e: unknown) {
                            setError(e instanceof Error ? e.message : "update_failed");
                          }
                        }}
                      >
                        {s.is_active ? "Deactivate" : "Activate"}
                      </button>
                      <button
                        type="button"
                        className="btn btn-ghost btn-sm"
                        onClick={() => {
                          setMapOpen({ staffId: s.id, label: `${s.full_name} (${s.staff_code})` });
                          setStationId("");
                          setMappedStations([]);
                          setMapLoading(true);
                          void (async () => {
                            try {
                              const res = await companyStaffStationMapsList(state.accessToken!, s.id);
                              setMappedStations((res.items ?? []) as MappedStationItem[]);
                            } catch (e: unknown) {
                              setError(e instanceof Error ? e.message : "station_list_failed");
                            } finally {
                              setMapLoading(false);
                            }
                          })();
                        }}
                      >
                        Map station
                      </button>
                      <button type="button" className="btn btn-ghost btn-sm" onClick={() => setDocOpen({ staffId: s.id, label: `${s.full_name} (${s.staff_code})` })}>
                        Add document
                      </button>
                      {canMapUser && (
                        <button
                          type="button"
                          className="btn btn-ghost btn-sm"
                          onClick={() => {
                            setLinkOpen({ staffId: s.id, label: `${s.full_name} (${s.staff_code})` });
                            setLinkUserOptionId("");
                            setLinkedUsers([]);
                            setLinkLoading(true);
                            void (async () => {
                              try {
                                const res = await companyStaffUserLinksList(state.accessToken!, s.id);
                                setLinkedUsers(res.items ?? []);
                              } catch (e: unknown) {
                                setError(e instanceof Error ? e.message : "link_list_failed");
                              } finally {
                                setLinkLoading(false);
                              }
                            })();
                          }}
                        >
                          Link login user
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
              {items.length === 0 && (
                <tr>
                  <td colSpan={6} className="cell-muted" style={{ padding: "var(--space-4)" }}>
                    {loading ? "Loading…" : "No staff found"}
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

      {createOpen && (
        <div className="modal-backdrop" role="presentation" onClick={() => setCreateOpen(false)}>
          <div className="modal-card" role="dialog" aria-modal="true" aria-labelledby="staff-create-title" onClick={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <h2 id="staff-create-title" className="modal-title">
                New staff
              </h2>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setCreateOpen(false)}>
                Close
              </button>
            </div>
            <div className="form-grid">
              <div className="field">
                <label className="field-label" htmlFor="staff-code">
                  Staff code
                </label>
                <input id="staff-code" className="input" value={sc} onChange={(e) => setSc(e.target.value)} placeholder="S001" />
              </div>
              <div className="field">
                <label className="field-label" htmlFor="staff-name">
                  Full name
                </label>
                <input id="staff-name" className="input" value={fn} onChange={(e) => setFn(e.target.value)} />
              </div>
              <div className="field">
                <label className="field-label" htmlFor="staff-mobile">
                  Mobile
                </label>
                <input id="staff-mobile" className="input" value={mb} onChange={(e) => setMb(e.target.value)} />
              </div>
              <div className="field">
                <label className="field-label" htmlFor="staff-email">
                  Email
                </label>
                <input id="staff-email" className="input" value={em} onChange={(e) => setEm(e.target.value)} />
              </div>
              <button
                type="button"
                className="btn btn-primary"
                disabled={!sc.trim() || !fn.trim()}
                onClick={async () => {
                  setError(null);
                  try {
                    await companyStaffCreate(state.accessToken!, { staffCode: sc, fullName: fn, mobile: mb, email: em });
                    setCreateOpen(false);
                    setSc("");
                    setFn("");
                    setMb("");
                    setEm("");
                    await load(false);
                  } catch (e: unknown) {
                    setError(e instanceof Error ? e.message : "create_failed");
                  }
                }}
              >
                Create
              </button>
            </div>
          </div>
        </div>
      )}

      {editOpen && (
        <div className="modal-backdrop" role="presentation" onClick={() => !editSaving && setEditOpen(null)}>
          <div className="modal-card" role="dialog" aria-modal="true" aria-labelledby="staff-edit-title" onClick={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <div>
                <h2 id="staff-edit-title" className="modal-title">
                  Edit staff
                </h2>
                <p className="muted" style={{ margin: "0.35rem 0 0" }}>
                  {editOpen.label} · Code cannot be changed.
                </p>
              </div>
              <button type="button" className="btn btn-secondary btn-sm" disabled={editSaving} onClick={() => setEditOpen(null)}>
                Close
              </button>
            </div>
            <div className="form-grid">
              <div className="field">
                <label className="field-label" htmlFor="staff-edit-code">
                  Staff code
                </label>
                <input id="staff-edit-code" className="input" value={editOpen.staffCode} disabled />
              </div>
              <div className="field">
                <label className="field-label" htmlFor="staff-edit-name">
                  Full name
                </label>
                <input id="staff-edit-name" className="input" value={editFn} onChange={(e) => setEditFn(e.target.value)} />
              </div>
              <div className="field">
                <label className="field-label" htmlFor="staff-edit-mobile">
                  Mobile
                </label>
                <input id="staff-edit-mobile" className="input" value={editMb} onChange={(e) => setEditMb(e.target.value)} />
              </div>
              <div className="field">
                <label className="field-label" htmlFor="staff-edit-email">
                  Email
                </label>
                <input id="staff-edit-email" className="input" value={editEm} onChange={(e) => setEditEm(e.target.value)} />
              </div>
              <div className="field">
                <label className="field-label" htmlFor="staff-edit-status">
                  Status
                </label>
                <select id="staff-edit-status" className="select" value={editStatus} onChange={(e) => setEditStatus(e.target.value)}>
                  <option value="active">active</option>
                  <option value="on_hold">on_hold</option>
                  <option value="inactive">inactive</option>
                </select>
              </div>
              <button
                type="button"
                className="btn btn-primary"
                disabled={editSaving || !editFn.trim()}
                onClick={async () => {
                  setError(null);
                  setEditSaving(true);
                  try {
                    await companyStaffUpdate(state.accessToken!, {
                      staffId: editOpen.staffId,
                      fullName: editFn.trim(),
                      mobile: editMb.trim() ? editMb.trim() : null,
                      email: editEm.trim() ? editEm.trim() : null,
                      status: editStatus
                    });
                    setEditOpen(null);
                    await load(false);
                  } catch (e: unknown) {
                    setError(e instanceof Error ? e.message : "update_failed");
                  } finally {
                    setEditSaving(false);
                  }
                }}
              >
                {editSaving ? "Saving…" : "Save changes"}
              </button>
            </div>
          </div>
        </div>
      )}

      {mapOpen && (
        <div className="modal-backdrop" role="presentation" onClick={() => setMapOpen(null)}>
          <div className="modal-card" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <h2 className="modal-title">Map station</h2>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setMapOpen(null)}>
                Close
              </button>
            </div>
            <p className="muted">{mapOpen.label}</p>
            <div className="form-grid mt-4">
              <select className="select" value={stationId} onChange={(e) => setStationId(e.target.value)}>
                <option value="" disabled>
                  Select station…
                </option>
                {stations.map((st) => (
                  <option key={st.id} value={st.id}>
                    {st.name} ({st.code})
                  </option>
                ))}
              </select>
              {stations.length === 0 && <div className="muted">No stations loaded. Create a station in Org → stations, then refresh.</div>}
              <button
                type="button"
                className="btn btn-primary"
                disabled={!stationId || mapBusy}
                onClick={async () => {
                  setError(null);
                  try {
                    setMapBusy(true);
                    await companyStaffMapStation(state.accessToken!, {
                      staffId: mapOpen.staffId,
                      stationId,
                      isPrimary: false,
                      isActive: true
                    });
                    const res = await companyStaffStationMapsList(state.accessToken!, mapOpen.staffId);
                    setMappedStations((res.items ?? []) as MappedStationItem[]);
                    setStationId("");
                  } catch (e: unknown) {
                    setError(e instanceof Error ? e.message : "map_failed");
                  } finally {
                    setMapBusy(false);
                  }
                }}
              >
                Map
              </button>
            </div>

            <div className="mt-4">
              <div className="field-label">Mapped stations</div>
              {mapLoading ? (
                <div className="muted" style={{ marginTop: "0.35rem" }}>
                  Loading…
                </div>
              ) : mappedStations.filter((m) => m.isActive !== false).length === 0 ? (
                <div className="table-wrap" style={{ marginTop: "0.5rem" }}>
                  <table className="data-table">
                    <thead>
                      <tr>
                        <th>Station name</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr>
                        <td colSpan={2} className="cell-muted" style={{ padding: "var(--space-4)" }}>
                          None mapped yet.
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              ) : (
                <div className="table-wrap" style={{ marginTop: "0.5rem" }}>
                  <table className="data-table">
                    <thead>
                      <tr>
                        <th>Station name</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      {mappedStations
                        .filter((m) => m.isActive !== false)
                        .map((m) => (
                          <tr key={m.stationId}>
                            <td>{m.station?.name ? `${m.station.name} (${m.station.code})` : m.stationId}</td>
                            <td>
                              <button
                                type="button"
                                className="btn btn-secondary btn-sm"
                                disabled={mapBusy}
                                onClick={async () => {
                                  setMapBusy(true);
                                  setError(null);
                                  try {
                                    await companyStaffMapStation(state.accessToken!, {
                                      staffId: mapOpen.staffId,
                                      stationId: m.stationId,
                                      isPrimary: m.isPrimary,
                                      isActive: false
                                    });
                                    const res = await companyStaffStationMapsList(state.accessToken!, mapOpen.staffId);
                                    setMappedStations((res.items ?? []) as MappedStationItem[]);
                                  } catch (e: unknown) {
                                    setError(e instanceof Error ? e.message : "unmap_failed");
                                  } finally {
                                    setMapBusy(false);
                                  }
                                }}
                              >
                                Unmap
                              </button>
                            </td>
                          </tr>
                        ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {linkOpen && (
        <div className="modal-backdrop" role="presentation" onClick={() => setLinkOpen(null)}>
          <div className="modal-card" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <h2 className="modal-title">Link login user</h2>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setLinkOpen(null)}>
                Close
              </button>
            </div>
            <p className="muted">
              Link a company user to staff record: <strong>{linkOpen.label}</strong>.
            </p>
            <div className="form-grid mt-4">
              <select
                className="select"
                value={linkUserOptionId}
                onChange={(e) => setLinkUserOptionId(e.target.value)}
              >
                <option value="">Select user…</option>
                {companyUsers.map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.displayName ?? u.email ?? "—"}
                  </option>
                ))}
              </select>
              <button
                type="button"
                className="btn btn-primary"
                disabled={!linkUserOptionId || linkBusy}
                onClick={async () => {
                  setError(null);
                  try {
                    setLinkBusy(true);
                    await companyStaffMapUser(state.accessToken!, { userId: linkUserOptionId, staffId: linkOpen.staffId, isActive: true });
                    const res = await companyStaffUserLinksList(state.accessToken!, linkOpen.staffId);
                    setLinkedUsers(res.items ?? []);
                    setLinkUserOptionId("");
                  } catch (e: unknown) {
                    setError(e instanceof Error ? e.message : "map_user_failed");
                  } finally {
                    setLinkBusy(false);
                  }
                }}
              >
                Save mapping
              </button>
            </div>

            <div className="mt-4">
              <div className="field-label">Linked users</div>
              {linkLoading ? (
                <div className="muted" style={{ marginTop: "0.35rem" }}>
                  Loading…
                </div>
              ) : (linkedUsers ?? []).filter((x: any) => x?.isActive !== false && x?.is_active !== false).length === 0 ? (
                <div className="table-wrap" style={{ marginTop: "0.5rem" }}>
                  <table className="data-table">
                    <thead>
                      <tr>
                        <th>User name</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr>
                        <td colSpan={2} className="cell-muted" style={{ padding: "var(--space-4)" }}>
                          None linked yet.
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              ) : (
                <div className="table-wrap" style={{ marginTop: "0.5rem" }}>
                  <table className="data-table">
                    <thead>
                      <tr>
                        <th>User name</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      {(linkedUsers ?? [])
                        .filter((x: any) => x?.isActive !== false && x?.is_active !== false)
                        .map((x: any) => (
                          <tr key={String(x?.userId ?? x?.ams_user_id ?? "")}>
                            <td>{x?.user?.display_name ?? x?.user?.displayName ?? x?.user?.email ?? "—"}</td>
                            <td>
                              <button
                                type="button"
                                className="btn btn-secondary btn-sm"
                                disabled={linkBusy}
                                onClick={async () => {
                                  const userId = String(x?.userId ?? x?.ams_user_id ?? "").trim();
                                  if (!userId) return;
                                  setError(null);
                                  try {
                                    setLinkBusy(true);
                                    await companyStaffMapUser(state.accessToken!, { userId, staffId: linkOpen.staffId, isActive: false });
                                    const res = await companyStaffUserLinksList(state.accessToken!, linkOpen.staffId);
                                    setLinkedUsers(res.items ?? []);
                                  } catch (e: unknown) {
                                    setError(e instanceof Error ? e.message : "unlink_failed");
                                  } finally {
                                    setLinkBusy(false);
                                  }
                                }}
                              >
                                Unlink
                              </button>
                            </td>
                          </tr>
                        ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {docOpen && (
        <div className="modal-backdrop" role="presentation" onClick={() => setDocOpen(null)}>
          <div className="modal-card" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <h2 className="modal-title">Add document (metadata)</h2>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setDocOpen(null)}>
                Close
              </button>
            </div>
            <p className="muted">{docOpen.label}</p>
            <div className="form-grid mt-4">
              <div className="field">
                <label className="field-label">Type</label>
                <input className="input" value={docType} onChange={(e) => setDocType(e.target.value)} />
              </div>
              <div className="field">
                <label className="field-label">Number</label>
                <input className="input" value={docNo} onChange={(e) => setDocNo(e.target.value)} />
              </div>
              <div className="field">
                <label className="field-label">Storage bucket</label>
                <input className="input" value={bucket} onChange={(e) => setBucket(e.target.value)} />
              </div>
              <div className="field">
                <label className="field-label">Storage path</label>
                <input className="input" value={path} onChange={(e) => setPath(e.target.value)} placeholder="company/<id>/staff/<id>/doc.pdf" />
              </div>
              <button
                type="button"
                className="btn btn-primary"
                disabled={!docType.trim()}
                onClick={async () => {
                  setError(null);
                  try {
                    await companyStaffAddDocument(state.accessToken!, {
                      staffId: docOpen.staffId,
                      documentType: docType,
                      documentNumber: docNo || null,
                      storageBucket: bucket || null,
                      storagePath: path || null
                    });
                    setDocOpen(null);
                    setDocType("ID");
                    setDocNo("");
                    setBucket("staff-documents");
                    setPath("");
                  } catch (e: unknown) {
                    setError(e instanceof Error ? e.message : "doc_failed");
                  }
                }}
              >
                Save
              </button>
            </div>
          </div>
        </div>
      )}
    </Layout>
  );
}
