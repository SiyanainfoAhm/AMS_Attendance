import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useAuth } from "../../auth/AuthContext";

export function LoginPage() {
  const { login } = useAuth();
  const nav = useNavigate();
  const [email, setEmail] = useState("admin@demo.local");
  const [password, setPassword] = useState("ChangeMe@123");
  const [error, setError] = useState<string | null>(null);

  return (
    <div className="auth-page">
      <div className="auth-card">
        <div className="auth-hero">
          <div className="auth-logo" aria-hidden />
          <h1 className="auth-title">Welcome back</h1>
          <p className="auth-subtitle">Sign in to the Attendance Management admin console</p>
        </div>
        <div className="form-grid">
          <div className="field">
            <label className="field-label" htmlFor="login-email">
              Email
            </label>
            <input
              id="login-email"
              className="input"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoComplete="username"
            />
          </div>
          <div className="field">
            <label className="field-label" htmlFor="login-password">
              Password
            </label>
            <input
              id="login-password"
              className="input"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              type="password"
              autoComplete="current-password"
            />
          </div>
          <p className="auth-subtitle" style={{ margin: 0, fontSize: "0.9rem" }}>
            <Link to="/forgot-password">Forgot password?</Link>
          </p>
          <button
            type="button"
            className="btn btn-primary"
            style={{ width: "100%", paddingTop: "0.65rem", paddingBottom: "0.65rem" }}
            onClick={async () => {
              setError(null);
              try {
                const { companies } = await login(email, password);
                if (companies.length === 1) nav("/select-company?auto=1");
                else nav("/select-company");
              } catch (e: unknown) {
                setError(e instanceof Error ? e.message : "login_failed");
              }
            }}
          >
            Sign in
          </button>
          {error && <div className="alert alert-error">{error}</div>}
        </div>
      </div>
    </div>
  );
}
