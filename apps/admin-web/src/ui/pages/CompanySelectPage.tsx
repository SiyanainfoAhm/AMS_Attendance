import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../../auth/AuthContext";
import { amsMe } from "../../lib/amsApi";

export function CompanySelectPage() {
  const { state, selectCompany } = useAuth();
  const nav = useNavigate();
  const [companies, setCompanies] = useState<any[]>([]);
  const [companyId, setCompanyId] = useState<string>("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      if (!state.accessToken) {
        nav("/login");
        return;
      }
      try {
        const me = await amsMe(state.accessToken);
        const list = (me.companies ?? []).map((c: any) => ({
          id: c.company_id ?? c.id,
          code: c.company_code ?? c.code,
          name: c.company_name ?? c.name
        }));
        setCompanies(list);
        if (list.length === 1) setCompanyId(list[0].id);
      } catch (e: unknown) {
        setError(e instanceof Error ? e.message : "failed_to_load_companies");
      }
    })();
  }, [nav, state.accessToken]);

  return (
    <div className="auth-page">
      <div className="auth-card auth-card-wide">
        <div className="auth-hero">
          <div className="auth-logo" aria-hidden />
          <h1 className="auth-title">Choose company</h1>
          <p className="auth-subtitle">Select the workspace you want to manage</p>
        </div>
        <div className="form-grid">
          <div className="field">
            <label className="field-label" htmlFor="company-select">
              Company
            </label>
            <select
              id="company-select"
              className="select"
              value={companyId}
              onChange={(e) => setCompanyId(e.target.value)}
            >
              <option value="" disabled>
                Select a company…
              </option>
              {companies.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name} ({c.code})
                </option>
              ))}
            </select>
          </div>
          <button
            type="button"
            className="btn btn-primary"
            style={{ width: "100%", paddingTop: "0.65rem", paddingBottom: "0.65rem" }}
            disabled={!companyId}
            onClick={async () => {
              setError(null);
              try {
                await selectCompany(companyId);
                nav("/");
              } catch (e: unknown) {
                setError(e instanceof Error ? e.message : "select_company_failed");
              }
            }}
          >
            Continue
          </button>
          {error && <div className="alert alert-error">{error}</div>}
        </div>
      </div>
    </div>
  );
}
