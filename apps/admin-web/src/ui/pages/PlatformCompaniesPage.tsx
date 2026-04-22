import { useEffect, useMemo, useState } from "react";
import { Layout } from "../components/Layout";
import { useAuth } from "../../auth/AuthContext";
import { platformCompaniesList, platformCompanyCreate, platformCompanyUpdate } from "../../lib/amsApi";
import { Pagination } from "../components/Pagination";

type Company = { id: string; code: string; name: string; is_active: boolean; created_at: string };

export function PlatformCompaniesPage() {
  const { state } = useAuth();
  const [items, setItems] = useState<Company[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(20);
  const [q, setQ] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const [createOpen, setCreateOpen] = useState(false);
  const [newCode, setNewCode] = useState("");
  const [newName, setNewName] = useState("");
  const [newTz, setNewTz] = useState("Asia/Kolkata");

  const pageCount = useMemo(() => Math.max(1, Math.ceil(total / pageSize)), [total, pageSize]);

  async function load() {
    if (!state.accessToken) return;
    setLoading(true);
    setError(null);
    try {
      const res = await platformCompaniesList(state.accessToken, { page, pageSize, q: q.trim() || undefined });
      setItems(res.items ?? []);
      setTotal(res.total ?? 0);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "failed_to_load");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, pageSize]);

  return (
    <Layout>
      <div className="page-stack">
        <div className="page-head">
          <div className="page-head-text">
            <h1 className="page-title">Companies</h1>
            <p className="page-subtitle">Platform-wide company directory</p>
          </div>
          <div className="page-actions">
            <button type="button" className="btn btn-primary" onClick={() => setCreateOpen(true)}>
              New company
            </button>
          </div>
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
                <th>Code</th>
                <th>Name</th>
                <th>Active</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {items.map((c) => (
                <tr key={c.id}>
                  <td className="cell-strong">{c.code}</td>
                  <td>{c.name}</td>
                  <td>{c.is_active ? "Yes" : "No"}</td>
                  <td>
                    <div className="table-actions">
                      <button
                        type="button"
                        className="btn btn-secondary btn-sm"
                        onClick={async () => {
                          const next = !c.is_active;
                          try {
                            await platformCompanyUpdate(state.accessToken!, { companyId: c.id, isActive: next });
                            await load();
                          } catch (e: unknown) {
                            setError(e instanceof Error ? e.message : "update_failed");
                          }
                        }}
                      >
                        {c.is_active ? "Deactivate" : "Activate"}
                      </button>
                      <button
                        type="button"
                        className="btn btn-ghost btn-sm"
                        onClick={async () => {
                          const name = prompt("Company name", c.name);
                          if (!name) return;
                          try {
                            await platformCompanyUpdate(state.accessToken!, { companyId: c.id, name });
                            await load();
                          } catch (e: unknown) {
                            setError(e instanceof Error ? e.message : "update_failed");
                          }
                        }}
                      >
                        Rename
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {items.length === 0 && (
                <tr>
                  <td colSpan={4} className="cell-muted" style={{ padding: "var(--space-4)" }}>
                    {loading ? "Loading…" : "No companies found"}
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
          <div className="modal-card" role="dialog" aria-modal="true" aria-labelledby="co-create-title" onClick={(e) => e.stopPropagation()}>
            <div className="modal-head">
              <h2 id="co-create-title" className="modal-title">
                New company
              </h2>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setCreateOpen(false)}>
                Close
              </button>
            </div>
            <div className="form-grid">
              <div className="field">
                <label className="field-label">Code</label>
                <input className="input" value={newCode} onChange={(e) => setNewCode(e.target.value)} placeholder="ACME" />
              </div>
              <div className="field">
                <label className="field-label">Name</label>
                <input className="input" value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="Acme Pvt Ltd" />
              </div>
              <div className="field">
                <label className="field-label">Timezone</label>
                <input className="input" value={newTz} onChange={(e) => setNewTz(e.target.value)} placeholder="Asia/Kolkata" />
              </div>
              <button
                type="button"
                className="btn btn-primary"
                disabled={!newCode.trim() || !newName.trim()}
                onClick={async () => {
                  setError(null);
                  try {
                    await platformCompanyCreate(state.accessToken!, { code: newCode, name: newName, timezone: newTz });
                    setCreateOpen(false);
                    setNewCode("");
                    setNewName("");
                    await load();
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
    </Layout>
  );
}
