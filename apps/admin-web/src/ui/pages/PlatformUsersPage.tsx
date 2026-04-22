import { useEffect, useMemo, useState } from "react";
import { Layout } from "../components/Layout";
import { useAuth } from "../../auth/AuthContext";
import { Pagination } from "../components/Pagination";
import {
  platformUserAssignRole,
  platformUserCreate,
  platformUserCompanyMapsList,
  platformUserMapCompany,
  platformUserRoleMapsList,
  platformUserSetActive,
  platformUserUpdate,
  platformUsersList
} from "../../lib/amsApi";

type UserRow = {
  id: string;
  display_name: string;
  email: string;
  is_active: boolean;
  is_platform_super_admin: boolean;
  created_at: string;
};

type CompanyRef = {
  id: string;
  code: string;
  name: string;
  is_active?: boolean;
};

type MappedCompanyItem = {
  companyId: string;
  isActive: boolean;
  updatedAt?: string | null;
  company?: CompanyRef | null;
};

type RoleRef = {
  id: string;
  code: string;
  name: string;
  is_active?: boolean;
  is_platform_role?: boolean;
  ams_company_id?: string | null;
};

type MappedRoleItem = {
  roleId: string;
  companyId: string | null;
  isActive: boolean;
  updatedAt?: string | null;
  role?: RoleRef | null;
};

export function PlatformUsersPage() {
  const { state } = useAuth();
  const [items, setItems] = useState<UserRow[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(20);
  const [q, setQ] = useState("");
  const [appliedQ, setAppliedQ] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const [metaCompanies, setMetaCompanies] = useState<any[]>([]);
  const [metaRoles, setMetaRoles] = useState<any[]>([]);

  const pageCount = useMemo(() => Math.max(1, Math.ceil(total / pageSize)), [total, pageSize]);

  async function load(includeMeta = false) {
    if (!state.accessToken) return;
    setLoading(true);
    setError(null);
    try {
      const res = await platformUsersList(state.accessToken, {
        page,
        pageSize,
        q: appliedQ.trim() || undefined,
        includeMeta
      });
      setItems(res.items ?? []);
      setTotal(res.total ?? 0);
      if (includeMeta) {
        setMetaCompanies(res.meta?.companies ?? []);
        setMetaRoles(res.meta?.roles ?? []);
      }
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "failed_to_load");
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
  }, [state.accessToken, page, pageSize, appliedQ]);

  const [createOpen, setCreateOpen] = useState(false);
  const [dn, setDn] = useState("");
  const [em, setEm] = useState("");
  const [pw, setPw] = useState("");
  const [isPSA, setIsPSA] = useState(false);

  const [editOpen, setEditOpen] = useState<null | { userId: string; email: string }>(null);
  const [edn, setEdn] = useState("");
  const [eem, setEem] = useState("");
  const [epw, setEpw] = useState("");
  const [eIsPSA, setEIsPSA] = useState(false);
  const [editSaving, setEditSaving] = useState(false);

  const [mapOpen, setMapOpen] = useState<null | { userId: string; email: string }>(null);
  const [mapCompanyId, setMapCompanyId] = useState("");
  const [mappedCompanies, setMappedCompanies] = useState<MappedCompanyItem[]>([]);
  const [mapBusy, setMapBusy] = useState(false);
  const [mapLoading, setMapLoading] = useState(false);

  // Companies list modal removed (use Map company modal instead)

  const [roleOpen, setRoleOpen] = useState<null | { userId: string; email: string }>(null);
  const [roleId, setRoleId] = useState("");
  const [roleCompanyId, setRoleCompanyId] = useState<string | "">("");
  const [roleLoading, setRoleLoading] = useState(false);
  const [roleBusy, setRoleBusy] = useState(false);
  const [mappedRoles, setMappedRoles] = useState<MappedRoleItem[]>([]);

  function companyLabel(companyId: string, company?: any | null) {
    if (company?.name && company?.code) return `${company.name} (${company.code})`;
    const fromMeta = metaCompanies.find((c) => c.id === companyId);
    if (fromMeta) return `${fromMeta.name} (${fromMeta.code})`;
    return companyId;
  }

  function mapRowCompanyId(m: any): string {
    return String(m?.companyId ?? m?.ams_company_id ?? m?.AMS_company_id ?? "").trim();
  }

  function normalizeMappedCompanies(input: any[]): MappedCompanyItem[] {
    const seen = new Set<string>();
    const out: MappedCompanyItem[] = [];
    for (const raw of input ?? []) {
      const companyId = mapRowCompanyId(raw);
      if (!companyId) continue;
      if (seen.has(companyId)) continue;
      seen.add(companyId);
      out.push({
        companyId,
        isActive: typeof raw?.isActive === "boolean" ? raw.isActive : typeof raw?.is_active === "boolean" ? raw.is_active : true,
        updatedAt: raw?.updatedAt ?? raw?.updated_at ?? null,
        company: raw?.company ?? raw?.ams_company ?? null
      });
    }
    return out;
  }

  function normalizeMappedRoles(input: any[]): MappedRoleItem[] {
    const seen = new Set<string>();
    const out: MappedRoleItem[] = [];
    for (const raw of input ?? []) {
      const roleId = String(raw?.roleId ?? raw?.ams_role_id ?? raw?.AMS_role_id ?? "").trim();
      const companyIdRaw = raw?.companyId ?? raw?.ams_company_id ?? raw?.AMS_company_id ?? null;
      const companyId = companyIdRaw == null || companyIdRaw === "" ? null : String(companyIdRaw);
      if (!roleId) continue;
      const key = `${roleId}:${companyId ?? ""}`;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({
        roleId,
        companyId,
        isActive: typeof raw?.isActive === "boolean" ? raw.isActive : typeof raw?.is_active === "boolean" ? raw.is_active : true,
        updatedAt: raw?.updatedAt ?? raw?.updated_at ?? null,
        role: raw?.role ?? raw?.ams_role ?? null
      });
    }
    return out;
  }

  return (
    <Layout>
      <div className="page-stack">
        <div className="page-head">
          <div className="page-head-text">
            <h1 className="page-title">Users</h1>
            <p className="page-subtitle">Platform user accounts (custom auth)</p>
          </div>
          <div className="page-actions">
            <button type="button" className="btn btn-primary" onClick={() => setCreateOpen(true)}>
              New user
            </button>
          </div>
        </div>

        <div className="toolbar">
          <input className="input toolbar-grow" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search by email or name" />
          <button
            type="button"
            className="btn btn-secondary"
            onClick={() => {
              setAppliedQ(q.trim());
              setPage(1);
            }}
          >
            Search
          </button>
          <button
            type="button"
            className="btn btn-ghost"
            onClick={() => {
              setQ("");
              setAppliedQ("");
              setPage(1);
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
                <th>Name</th>
                <th>Email</th>
                <th>Active</th>
                <th>Platform SA</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {items.map((u) => (
                <tr key={u.id}>
                  <td className="cell-strong">{u.display_name}</td>
                  <td>{u.email}</td>
                  <td>{u.is_active ? "Yes" : "No"}</td>
                  <td>{u.is_platform_super_admin ? "Yes" : "No"}</td>
                  <td>
                    <div className="table-actions">
                      <button
                        type="button"
                        className="btn btn-ghost btn-sm"
                        onClick={() => {
                          setEditOpen({ userId: u.id, email: u.email });
                          setEdn(u.display_name ?? "");
                          setEem(u.email ?? "");
                          setEpw("");
                          setEIsPSA(Boolean(u.is_platform_super_admin));
                        }}
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        className="btn btn-secondary btn-sm"
                        onClick={async () => {
                          try {
                            await platformUserSetActive(state.accessToken!, { userId: u.id, isActive: !u.is_active });
                            await load(false);
                          } catch (e: unknown) {
                            setError(e instanceof Error ? e.message : "update_failed");
                          }
                        }}
                      >
                        {u.is_active ? "Deactivate" : "Activate"}
                      </button>
                      <button
                        type="button"
                        className="btn btn-ghost btn-sm"
                        onClick={() => {
                          setMapOpen({ userId: u.id, email: u.email });
                          setMapCompanyId("");
                          setMappedCompanies([]);
                          setMapLoading(true);
                          void load(true);
                          void (async () => {
                            try {
                              const res = await platformUserCompanyMapsList(state.accessToken!, u.id);
                              setMappedCompanies(normalizeMappedCompanies(res.items ?? []));
                            } catch (e: unknown) {
                              setError(e instanceof Error ? e.message : "map_list_failed");
                            } finally {
                              setMapLoading(false);
                            }
                          })();
                        }}
                      >
                        Map company
                      </button>
                      <button
                        type="button"
                        className="btn btn-ghost btn-sm"
                        onClick={() => {
                          setRoleOpen({ userId: u.id, email: u.email });
                          setRoleId("");
                          setRoleCompanyId("");
                          setMappedRoles([]);
                          setRoleLoading(true);
                          void load(true);
                          void (async () => {
                            try {
                              const res = await platformUserRoleMapsList(state.accessToken!, u.id);
                              setMappedRoles(normalizeMappedRoles(res.items ?? []));
                            } catch (e: unknown) {
                              setError(e instanceof Error ? e.message : "role_list_failed");
                            } finally {
                              setRoleLoading(false);
                            }
                          })();
                        }}
                      >
                        Assign role
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {items.length === 0 && (
                <tr>
                  <td colSpan={5} className="cell-muted" style={{ padding: "var(--space-4)" }}>
                    {loading ? "Loading…" : "No users found"}
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
          pageSizeOptions={[10, 20, 50, 100]}
        />
      </div>

      {createOpen && (
        <div className="modal-backdrop" role="presentation" onClick={() => setCreateOpen(false)}>
          <div className="modal-card" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <h2 className="modal-title">New user</h2>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setCreateOpen(false)}>
                Close
              </button>
            </div>
            <div className="form-grid">
              <div className="field">
                <label className="field-label">Display name</label>
                <input className="input" value={dn} onChange={(e) => setDn(e.target.value)} />
              </div>
              <div className="field">
                <label className="field-label">Email</label>
                <input className="input" value={em} onChange={(e) => setEm(e.target.value)} />
              </div>
              <div className="field">
                <label className="field-label">Temporary password</label>
                <input className="input" value={pw} onChange={(e) => setPw(e.target.value)} type="password" />
              </div>
              <label className="checkbox-row">
                <input type="checkbox" checked={isPSA} onChange={(e) => setIsPSA(e.target.checked)} />
                Platform Super Admin
              </label>
              <button
                type="button"
                className="btn btn-primary"
                disabled={!dn.trim() || !em.trim() || pw.length < 8}
                onClick={async () => {
                  setError(null);
                  try {
                    await platformUserCreate(state.accessToken!, {
                      displayName: dn,
                      email: em,
                      password: pw,
                      isPlatformSuperAdmin: isPSA
                    });
                    setCreateOpen(false);
                    setDn("");
                    setEm("");
                    setPw("");
                    setIsPSA(false);
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
          <div className="modal-card" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <div>
                <h2 className="modal-title">Edit user</h2>
                <p className="muted" style={{ margin: "0.35rem 0 0" }}>
                  {editOpen.email}
                </p>
              </div>
              <button type="button" className="btn btn-secondary btn-sm" disabled={editSaving} onClick={() => setEditOpen(null)}>
                Close
              </button>
            </div>
            <div className="form-grid">
              <div className="field">
                <label className="field-label">Display name</label>
                <input className="input" value={edn} onChange={(e) => setEdn(e.target.value)} />
              </div>
              <div className="field">
                <label className="field-label">Email</label>
                <input className="input" value={eem} onChange={(e) => setEem(e.target.value)} />
              </div>
              <div className="field">
                <label className="field-label">New password (optional)</label>
                <input className="input" value={epw} onChange={(e) => setEpw(e.target.value)} type="password" placeholder="Leave blank to keep unchanged" />
              </div>
              <label className="checkbox-row">
                <input type="checkbox" checked={eIsPSA} onChange={(e) => setEIsPSA(e.target.checked)} />
                Platform Super Admin
              </label>
              <button
                type="button"
                className="btn btn-primary"
                disabled={editSaving || !edn.trim() || !eem.trim() || (epw.length > 0 && epw.length < 8)}
                onClick={async () => {
                  setError(null);
                  setEditSaving(true);
                  try {
                    await platformUserUpdate(state.accessToken!, {
                      userId: editOpen.userId,
                      displayName: edn,
                      email: eem,
                      password: epw.trim() ? epw : undefined,
                      isPlatformSuperAdmin: eIsPSA
                    });
                    setEditOpen(null);
                    setEpw("");
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
              <h2 className="modal-title">Map company</h2>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setMapOpen(null)}>
                Close
              </button>
            </div>
            <p className="muted">{mapOpen.email}</p>
            <div className="form-grid mt-4">
              <select className="select" value={mapCompanyId} onChange={(e) => setMapCompanyId(e.target.value)}>
                <option value="" disabled>
                  Select company…
                </option>
                {metaCompanies.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name} ({c.code})
                  </option>
                ))}
              </select>
              <button
                type="button"
                className="btn btn-primary"
                disabled={!mapCompanyId || mapBusy}
                onClick={async () => {
                  setError(null);
                  try {
                    setMapBusy(true);
                    await platformUserMapCompany(state.accessToken!, { userId: mapOpen.userId, companyId: mapCompanyId, isActive: true });
                    const res = await platformUserCompanyMapsList(state.accessToken!, mapOpen.userId);
                    setMappedCompanies(normalizeMappedCompanies(res.items ?? []));
                    setMapCompanyId("");
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
              <div className="field-label">Mapped companies</div>
              {mapLoading ? (
                <div className="muted" style={{ marginTop: "0.35rem" }}>
                  Loading…
                </div>
              ) : mappedCompanies.filter((m) => m?.isActive !== false).length === 0 ? (
                <div className="muted" style={{ marginTop: "0.35rem" }}>
                  None mapped yet.
                </div>
              ) : (
                <div className="table-wrap" style={{ marginTop: "0.5rem" }}>
                  <table className="data-table">
                    <thead>
                      <tr>
                        <th>Company name</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      {mappedCompanies
                        .filter((m) => Boolean(m.companyId))
                        .filter((m) => m.isActive !== false)
                        .map((m) => (
                        <tr key={m.companyId}>
                          <td>
                            {companyLabel(m.companyId, m.company)}
                          </td>
                          <td>
                            <button
                              type="button"
                              className="btn btn-secondary btn-sm"
                              disabled={mapBusy}
                              onClick={async () => {
                                setMapBusy(true);
                                setError(null);
                                try {
                                  await platformUserMapCompany(state.accessToken!, {
                                    userId: mapOpen.userId,
                                    companyId: m.companyId,
                                    isActive: false
                                  });
                                  const res = await platformUserCompanyMapsList(state.accessToken!, mapOpen.userId);
                                  setMappedCompanies(normalizeMappedCompanies(res.items ?? []));
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

      {roleOpen && (
        <div className="modal-backdrop" role="presentation" onClick={() => setRoleOpen(null)}>
          <div className="modal-card" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <h2 className="modal-title">Assign role</h2>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setRoleOpen(null)}>
                Close
              </button>
            </div>
            <p className="muted">{roleOpen.email}</p>
            <div className="form-grid mt-4">
              {metaRoles.length === 0 && (
                <div className="alert alert-error">
                  Roles list is empty. Click <strong>Reload roles</strong>. If it still stays empty, ensure you selected a company and
                  your login user has <code>PLATFORM_USER_READ</code>.
                  <div style={{ marginTop: "var(--space-3)" }}>
                    <button type="button" className="btn btn-secondary btn-sm" onClick={() => void load(true)}>
                      Reload roles
                    </button>
                  </div>
                </div>
              )}
              <select className="select" value={roleCompanyId} onChange={(e) => setRoleCompanyId(e.target.value)}>
                <option value="">Role scope: Platform (global)</option>
                {metaCompanies.map((c) => (
                  <option key={c.id} value={c.id}>
                    Role scope: {c.name} ({c.code})
                  </option>
                ))}
              </select>
              <select className="select" value={roleId} onChange={(e) => setRoleId(e.target.value)}>
                <option value="" disabled>
                  Select role…
                </option>
                {metaRoles
                  .filter((r) => (roleCompanyId ? r.ams_company_id === roleCompanyId : r.ams_company_id == null))
                  .map((r) => (
                    <option key={r.id} value={r.id}>
                      {r.code} — {r.name}
                    </option>
                  ))}
              </select>
              <button
                type="button"
                className="btn btn-primary"
                disabled={!roleId || roleBusy}
                onClick={async () => {
                  setError(null);
                  try {
                    setRoleBusy(true);
                    await platformUserAssignRole(state.accessToken!, {
                      userId: roleOpen.userId,
                      roleId,
                      companyId: roleCompanyId || null,
                      isActive: true
                    });
                    const res = await platformUserRoleMapsList(state.accessToken!, roleOpen.userId);
                    setMappedRoles(normalizeMappedRoles(res.items ?? []));
                    setRoleId("");
                    setRoleCompanyId("");
                  } catch (e: unknown) {
                    setError(e instanceof Error ? e.message : "assign_failed");
                  } finally {
                    setRoleBusy(false);
                  }
                }}
              >
                Assign
              </button>
            </div>

            <div className="mt-4">
              <div className="field-label">Assigned roles</div>
              {roleLoading ? (
                <div className="muted" style={{ marginTop: "0.35rem" }}>
                  Loading…
                </div>
              ) : mappedRoles.filter((m) => m.isActive !== false).length === 0 ? (
                <div className="table-wrap" style={{ marginTop: "0.5rem" }}>
                  <table className="data-table">
                    <thead>
                      <tr>
                        <th>Role name</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr>
                        <td colSpan={2} className="cell-muted" style={{ padding: "var(--space-4)" }}>
                          None assigned yet.
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
                        <th>Role name</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      {mappedRoles
                        .filter((m) => m.isActive !== false)
                        .map((m) => (
                          <tr key={`${m.roleId}:${m.companyId ?? ""}`}>
                            <td>
                              {m.role?.code
                                ? `${m.role.code} — ${m.role.name}${m.companyId ? ` (${companyLabel(m.companyId)})` : " (Platform)"}`
                                : m.roleId}
                            </td>
                            <td>
                              <button
                                type="button"
                                className="btn btn-secondary btn-sm"
                                disabled={roleBusy}
                                onClick={async () => {
                                  setRoleBusy(true);
                                  setError(null);
                                  try {
                                    await platformUserAssignRole(state.accessToken!, {
                                      userId: roleOpen.userId,
                                      roleId: m.roleId,
                                      companyId: m.companyId,
                                      isActive: false
                                    });
                                    const res = await platformUserRoleMapsList(state.accessToken!, roleOpen.userId);
                                    setMappedRoles(normalizeMappedRoles(res.items ?? []));
                                  } catch (e: unknown) {
                                    setError(e instanceof Error ? e.message : "unassign_failed");
                                  } finally {
                                    setRoleBusy(false);
                                  }
                                }}
                              >
                                Remove
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
    </Layout>
  );
}
