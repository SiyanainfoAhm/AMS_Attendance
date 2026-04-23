import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Layout } from "../components/Layout";
import { useAuth } from "../../auth/AuthContext";
import { amsChangePassword } from "../../lib/amsApi";

export function ProfilePage() {
  const { state, logout, refreshMe } = useAuth();
  const nav = useNavigate();

  const [oldPassword, setOldPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!state.accessToken) {
      nav("/login");
      return;
    }
    if (!state.companyId) {
      nav("/select-company");
      return;
    }
    void refreshMe().catch(() => {
      // ignore: /me failures are surfaced elsewhere when user navigates
    });
  }, [nav, refreshMe, state.accessToken, state.companyId]);

  async function submit() {
    if (!state.accessToken) return;
    setError(null);

    if (newPassword.length < 8) {
      setError("New password must be at least 8 characters.");
      return;
    }
    if (newPassword !== confirmPassword) {
      setError("New password and confirmation do not match.");
      return;
    }
    if (oldPassword === newPassword) {
      setError("New password must be different from your current password.");
      return;
    }

    setSubmitting(true);
    try {
      await amsChangePassword(state.accessToken, oldPassword, newPassword);
      await logout();
      nav("/login?passwordChanged=1");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "change_password_failed");
    } finally {
      setSubmitting(false);
    }
  }

  const email = state.me?.user?.email ? String(state.me.user.email) : "—";
  const displayName = state.me?.user?.display_name ? String(state.me.user.display_name) : "—";

  return (
    <Layout>
      <div className="page-stack">
        <div className="page-head">
          <div className="page-head-text">
            <h1 className="page-title">Profile</h1>
            <p className="page-subtitle">Account details and password security</p>
          </div>
        </div>

        <div className="card" style={{ padding: "var(--space-3)" }}>
          <div className="section-title" style={{ marginBottom: "0.35rem" }}>
            Account
          </div>
          <div className="muted" style={{ marginBottom: "0.75rem" }}>
            Signed-in user context for this admin session.
          </div>

          <div className="form-grid" style={{ maxWidth: 720 }}>
            <div className="field">
              <div className="field-label">Display name</div>
              <div className="cell-strong">{displayName}</div>
            </div>
            <div className="field">
              <div className="field-label">Email</div>
              <div className="cell-strong">{email}</div>
            </div>
          </div>
        </div>

        <div className="card" style={{ padding: "var(--space-3)" }}>
          <div className="section-title" style={{ marginBottom: "0.35rem" }}>
            Change password
          </div>
          <div className="muted" style={{ marginBottom: "0.85rem" }}>
            For security, changing your password signs you out everywhere and ends active sessions.
          </div>

          <div className="form-grid" style={{ maxWidth: 520 }}>
            <div className="field">
              <label className="field-label" htmlFor="pw-old">
                Current password
              </label>
              <input
                id="pw-old"
                className="input"
                type="password"
                autoComplete="current-password"
                value={oldPassword}
                onChange={(e) => setOldPassword(e.target.value)}
                disabled={submitting}
              />
            </div>
            <div className="field">
              <label className="field-label" htmlFor="pw-new">
                New password
              </label>
              <input
                id="pw-new"
                className="input"
                type="password"
                autoComplete="new-password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                disabled={submitting}
              />
            </div>
            <div className="field">
              <label className="field-label" htmlFor="pw-confirm">
                Confirm new password
              </label>
              <input
                id="pw-confirm"
                className="input"
                type="password"
                autoComplete="new-password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                disabled={submitting}
              />
            </div>

            <button type="button" className="btn btn-primary" disabled={submitting} onClick={() => void submit()}>
              {submitting ? "Updating…" : "Update password"}
            </button>
          </div>

          {error && <div className="alert alert-error">{error}</div>}
        </div>
      </div>
    </Layout>
  );
}
