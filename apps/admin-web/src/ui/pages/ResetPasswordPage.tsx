import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { amsConfirmPasswordReset } from "../../lib/amsApi";

export function ResetPasswordPage() {
  const [params] = useSearchParams();
  const nav = useNavigate();
  const tokenFromUrl = useMemo(() => params.get("token")?.trim() ?? "", [params]);

  const [token, setToken] = useState(tokenFromUrl);
  const [password, setPassword] = useState("");

  useEffect(() => {
    if (tokenFromUrl) setToken(tokenFromUrl);
  }, [tokenFromUrl]);
  const [password2, setPassword2] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  return (
    <div className="auth-page">
      <div className="auth-card">
        <div className="auth-hero">
          <div className="auth-logo" aria-hidden />
          <h1 className="auth-title">Set new password</h1>
          <p className="auth-subtitle">Enter the reset token and your new password (at least 8 characters).</p>
        </div>
        {!success ? (
          <div className="form-grid">
            <div className="field">
              <label className="field-label" htmlFor="reset-token">
                Reset token
              </label>
              <input
                id="reset-token"
                className="input"
                value={token}
                onChange={(e) => setToken(e.target.value)}
                autoComplete="off"
              />
            </div>
            <div className="field">
              <label className="field-label" htmlFor="reset-pass">
                New password
              </label>
              <input
                id="reset-pass"
                className="input"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                type="password"
                autoComplete="new-password"
              />
            </div>
            <div className="field">
              <label className="field-label" htmlFor="reset-pass2">
                Confirm password
              </label>
              <input
                id="reset-pass2"
                className="input"
                value={password2}
                onChange={(e) => setPassword2(e.target.value)}
                type="password"
                autoComplete="new-password"
              />
            </div>
            <button
              type="button"
              className="btn btn-primary"
              style={{ width: "100%", paddingTop: "0.65rem", paddingBottom: "0.65rem" }}
              onClick={async () => {
                setError(null);
                if (password.length < 8) {
                  setError("Password must be at least 8 characters.");
                  return;
                }
                if (password !== password2) {
                  setError("Passwords do not match.");
                  return;
                }
                if (!token.trim()) {
                  setError("Reset token is required.");
                  return;
                }
                try {
                  await amsConfirmPasswordReset(token.trim(), password);
                  setSuccess(true);
                } catch (e: unknown) {
                  setError(e instanceof Error ? e.message : "reset_failed");
                }
              }}
            >
              Update password
            </button>
            {error && <div className="alert alert-error">{error}</div>}
            <p className="auth-subtitle" style={{ marginTop: "0.5rem", fontSize: "0.9rem" }}>
              <Link to="/login">Back to sign in</Link>
            </p>
          </div>
        ) : (
          <div className="form-grid">
            <div className="alert alert-error" style={{ background: "var(--surface-2)", borderColor: "var(--border)" }}>
              Your password was updated. You can sign in with the new password.
            </div>
            <button type="button" className="btn btn-primary" onClick={() => nav("/login")}>
              Go to sign in
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
