import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Layout } from "../components/Layout";
import { useAuth } from "../../auth/AuthContext";
import { companySupportCreate, companySupportList, companySupportSetStatus } from "../../lib/amsApi";

type Ticket = {
  id: string;
  ticket_code: string;
  title: string;
  description: string | null;
  priority: string;
  status: string;
  opened_at: string;
  due_by: string | null;
  closed_at: string | null;
};

const STATUSES = ["open", "in_progress", "resolved", "closed", "cancelled"] as const;

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

function daysAgoIso(n: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
}

export function SupportPage() {
  const { state } = useAuth();
  const nav = useNavigate();
  const perms: string[] = state.me?.permissions ?? [];
  const isPlatform = state.me?.user?.is_platform_super_admin === true;
  const canWrite = isPlatform || perms.includes("COMPANY_SUPPORT_WRITE");

  const [items, setItems] = useState<Ticket[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [pageSize] = useState(25);
  const [statusFilter, setStatusFilter] = useState("");
  const [from, setFrom] = useState(daysAgoIso(30));
  const [to, setTo] = useState(todayIso);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [createOpen, setCreateOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [priority, setPriority] = useState("medium");

  const pageCount = useMemo(() => Math.max(1, Math.ceil(total / pageSize)), [total, pageSize]);

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
    if (from > to) {
      setError("From date must be on or before To date.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const res = await companySupportList(state.accessToken, {
        page,
        pageSize,
        status: statusFilter || undefined,
        from,
        to
      });
      setItems(res.items ?? []);
      setTotal(res.total ?? 0);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "load_failed");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (state.accessToken && state.companyId) void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.accessToken, state.companyId, page, statusFilter, from, to]);

  async function createTicket() {
    if (!state.accessToken) return;
    setError(null);
    try {
      await companySupportCreate(state.accessToken, { title, description: description || undefined, priority });
      setTitle("");
      setDescription("");
      setPriority("medium");
      setCreateOpen(false);
      setPage(1);
      await load();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "create_failed");
    }
  }

  function closeCreateModal() {
    setCreateOpen(false);
    setTitle("");
    setDescription("");
    setPriority("medium");
  }

  async function setStatus(id: string, status: string) {
    if (!state.accessToken) return;
    setError(null);
    try {
      await companySupportSetStatus(state.accessToken, { id, status });
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
            <h1 className="page-title">Support</h1>
            <p className="page-subtitle">Company tickets and issues</p>
          </div>
          <div className="page-actions date-toolbar filter-toolbar">
            {canWrite && (
              <button type="button" className="btn btn-primary" onClick={() => setCreateOpen(true)}>
                New ticket
              </button>
            )}
            <input className="input input-date" type="date" value={from} onChange={(e) => { setFrom(e.target.value); setPage(1); }} />
            <span className="muted" style={{ whiteSpace: "nowrap" }}>
              to
            </span>
            <input className="input input-date" type="date" value={to} onChange={(e) => { setTo(e.target.value); setPage(1); }} />
            <select
              className="select"
              value={statusFilter}
              onChange={(e) => {
                setStatusFilter(e.target.value);
                setPage(1);
              }}
            >
              <option value="">All statuses</option>
              {STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
            <button type="button" className="btn btn-secondary" onClick={() => void load()} disabled={loading || from > to}>
              Refresh
            </button>
          </div>
        </div>

        {error && <div className="alert alert-error">{error}</div>}

        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Code</th>
                <th>Title</th>
                <th>Priority</th>
                <th>Status</th>
                <th>Opened</th>
              </tr>
            </thead>
            <tbody>
              {items.map((t) => (
                <tr key={t.id}>
                  <td className="cell-strong">{t.ticket_code}</td>
                  <td>
                    <div>{t.title}</div>
                    {t.description && <div className="muted" style={{ marginTop: "var(--space-1)", fontSize: "0.85rem" }}>{t.description}</div>}
                  </td>
                  <td>{t.priority}</td>
                  <td>
                    {canWrite ? (
                      <select
                        className="select"
                        style={{ padding: "var(--space-1) var(--space-2)", fontSize: "0.85rem" }}
                        defaultValue={t.status}
                        key={`${t.id}-${t.status}`}
                        onChange={(e) => void setStatus(t.id, e.target.value)}
                      >
                        {STATUSES.map((s) => (
                          <option key={s} value={s}>
                            {s}
                          </option>
                        ))}
                      </select>
                    ) : (
                      t.status
                    )}
                  </td>
                  <td className="cell-muted" style={{ whiteSpace: "nowrap" }}>
                    {new Date(t.opened_at).toLocaleString()}
                  </td>
                </tr>
              ))}
              {items.length === 0 && (
                <tr>
                  <td colSpan={5} className="cell-muted" style={{ padding: "var(--space-4)" }}>
                    {loading ? "Loading…" : "No tickets"}
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
            <button type="button" className="btn btn-secondary btn-sm" disabled={page >= pageCount} onClick={() => setPage((p) => Math.min(pageCount, p + 1))}>
              Next
            </button>
          </div>
        </div>

        {canWrite && createOpen && (
          <div className="modal-backdrop" role="presentation" onClick={() => closeCreateModal()}>
            <div
              className="modal-card"
              role="dialog"
              aria-modal="true"
              aria-labelledby="support-create-title"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="modal-head">
                <h2 id="support-create-title" className="modal-title">
                  New ticket
                </h2>
                <button type="button" className="btn btn-secondary btn-sm" onClick={() => closeCreateModal()}>
                  Close
                </button>
              </div>
              <div className="form-grid" style={{ gap: "var(--space-3)" }}>
                <div className="form-grid-2">
                  <div className="field">
                    <label className="field-label" htmlFor="ticket-title">
                      Title
                    </label>
                    <input
                      id="ticket-title"
                      className="input"
                      placeholder="Title"
                      value={title}
                      onChange={(e) => setTitle(e.target.value)}
                      autoFocus
                    />
                  </div>
                  <div className="field">
                    <label className="field-label" htmlFor="ticket-priority">
                      Priority
                    </label>
                    <select id="ticket-priority" className="select" value={priority} onChange={(e) => setPriority(e.target.value)}>
                      <option value="low">low</option>
                      <option value="medium">medium</option>
                      <option value="high">high</option>
                      <option value="critical">critical</option>
                    </select>
                  </div>
                </div>
                <div className="field">
                  <label className="field-label" htmlFor="ticket-desc">
                    Description
                  </label>
                  <textarea
                    id="ticket-desc"
                    className="ams-textarea"
                    placeholder="Description (optional)"
                    value={description}
                    onChange={(e) => setDescription(e.target.value)}
                    rows={3}
                  />
                </div>
                <div className="toolbar" style={{ justifyContent: "flex-end", marginTop: "var(--space-1)" }}>
                  <button type="button" className="btn btn-secondary" onClick={() => closeCreateModal()}>
                    Cancel
                  </button>
                  <button type="button" className="btn btn-primary" onClick={() => void createTicket()} disabled={!title.trim() || loading}>
                    Create
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </Layout>
  );
}
