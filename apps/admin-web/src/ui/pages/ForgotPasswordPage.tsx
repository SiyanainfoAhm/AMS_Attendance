import { useState } from "react";
import { Link } from "react-router-dom";
import { amsRequestPasswordReset } from "../../lib/amsApi";

export function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [done, setDone] = useState(false);
  const [devToken, setDevToken] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  return (
    <div className="auth-page">
      <div className="auth-card">
        <div className="auth-hero">
          <div className="auth-logo" aria-hidden />
          <h1 className="auth-title">Reset password</h1>
          <p className="auth-subtitle">
            Enter your account email. If it exists, you can complete reset from the link we send (or use the
            dev token when the server is configured to return it).
          </p>
        </div>
        {!done ? (
          <div className="form-grid">
            <div className="field">
              <label className="field-label" htmlFor="forgot-email">
                Email
              </label>
              <input
                id="forgot-email"
                className="input"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="email"
              />
            </div>
            <button
              type="button"
              className="btn btn-primary"
              style={{ width: "100%", paddingTop: "0.65rem", paddingBottom: "0.65rem" }}
              onClick={async () => {
                setError(null);
                setDevToken(null);
                try {
                  const r = await amsRequestPasswordReset(email.trim());
                  if (r.reset_token) setDevToken(r.reset_token);
                  setDone(true);
                } catch (e: unknown) {
                  setError(e instanceof Error ? e.message : "request_failed");
                }
              }}
            >
              Send reset instructions
            </button>
            {error && <div className="alert alert-error">{error}</div>}
            <p className="auth-subtitle" style={{ marginTop: "0.5rem", fontSize: "0.9rem" }}>
              <Link to="/login">Back to sign in</Link>
            </p>
          </div>
        ) : (
          <div className="form-grid">
            <div className="alert alert-error" style={{ background: "var(--surface-2)", borderColor: "var(--border)" }}>
              If an account exists for that email, password reset instructions have been sent. Check your inbox
              (or your deployment&rsquo;s email integration).
            </div>
            {devToken && (
              <div className="field">
                <label className="field-label">Dev reset token (server flag)</label>
                <textarea className="input" readOnly rows={3} value={devToken} />
                <p className="auth-subtitle" style={{ marginTop: "0.35rem", fontSize: "0.85rem" }}>
                  Use &ldquo;Set new password&rdquo; with this token, or open{" "}
                  <Link to={`/reset-password?token=${encodeURIComponent(devToken)}`}>the reset page</Link>.
                </p>
              </div>
            )}
            <Link to="/login" className="btn btn-primary" style={{ textAlign: "center", textDecoration: "none" }}>
              Back to sign in
            </Link>
          </div>
        )}
      </div>
    </div>
  );
}
