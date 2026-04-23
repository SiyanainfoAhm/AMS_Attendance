import { NavLink, useNavigate } from "react-router-dom";
import { useAuth } from "../../auth/AuthContext";

export function Layout({ children }: { children: React.ReactNode }) {
  const { state, logout } = useAuth();
  const nav = useNavigate();

  const perms: string[] = state.me?.permissions ?? [];
  const isPlatform = state.me?.user?.is_platform_super_admin === true;

  const companyId = state.companyId;
  const selectedCompanyName =
    state.me?.selectedCompany?.name ??
    (Array.isArray(state.me?.companies)
      ? state.me.companies.find((c: any) => String(c?.id ?? c?.company_id ?? "") === String(companyId ?? ""))?.name ??
        state.me.companies.find((c: any) => String(c?.id ?? c?.company_id ?? "") === String(companyId ?? ""))?.company_name
      : null);
  const companyLabel = selectedCompanyName ? String(selectedCompanyName) : (companyId ?? "");

  const navItems = [
    { to: "/", label: "Dashboard", show: true },
    { to: "/platform/companies", label: "Companies", show: isPlatform || perms.includes("PLATFORM_COMPANY_READ") },
    { to: "/platform/users", label: "Users", show: isPlatform || perms.includes("PLATFORM_USER_READ") },
    { to: "/org", label: "Org", show: isPlatform || perms.includes("COMPANY_ORG_READ") },
    { to: "/staff", label: "Staff", show: isPlatform || perms.includes("COMPANY_STAFF_READ") },
    { to: "/attendance", label: "Attendance", show: isPlatform || perms.includes("COMPANY_ATTENDANCE_READ") },
    { to: "/audit", label: "Audit", show: isPlatform || perms.includes("COMPANY_ATTENDANCE_READ") },
    { to: "/reports", label: "Reports", show: isPlatform || perms.includes("COMPANY_REPORT_READ") },
    { to: "/support", label: "Support", show: isPlatform || perms.includes("COMPANY_SUPPORT_READ") },
    { to: "/profile", label: "Profile", show: true }
  ].filter((x) => x.show);

  return (
    <div className="ams-layout">
      <header className="ams-header">
        <div className="ams-brand">
          <div className="ams-logo" aria-hidden />
          <div>
            <div className="ams-brand-text">AMS Admin</div>
            <span className="ams-brand-badge">Attendance</span>
          </div>
        </div>
        <div className="ams-header-actions">
          {companyId && (
            <span className="ams-company-pill" title={companyId}>
              Company: {companyLabel}
            </span>
          )}
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={async () => {
              await logout();
              nav("/login");
            }}
          >
            Log out
          </button>
        </div>
      </header>

      <div className="ams-body">
        <aside className="ams-sidebar">
          <div className="ams-nav-title">Menu</div>
          <nav className="ams-nav" aria-label="Main">
            {navItems.map((i) => (
              <NavLink
                key={i.to}
                to={i.to}
                end={i.to === "/"}
                className={({ isActive }) => `ams-nav-link${isActive ? " is-active" : ""}`}
              >
                {i.label}
              </NavLink>
            ))}
          </nav>
        </aside>
        <main className="ams-main">{children}</main>
      </div>
    </div>
  );
}
