import { createBrowserRouter } from "react-router-dom";
import { LoginPage } from "./ui/pages/LoginPage";
import { ForgotPasswordPage } from "./ui/pages/ForgotPasswordPage";
import { ResetPasswordPage } from "./ui/pages/ResetPasswordPage";
import { CompanySelectPage } from "./ui/pages/CompanySelectPage";
import { DashboardPage } from "./ui/pages/DashboardPage";
import { PlatformCompaniesPage } from "./ui/pages/PlatformCompaniesPage";
import { PlatformUsersPage } from "./ui/pages/PlatformUsersPage";
import { OrgPage } from "./ui/pages/OrgPage";
import { StaffPage } from "./ui/pages/StaffPage";
import { AttendancePage } from "./ui/pages/AttendancePage";
import { ReportsPage } from "./ui/pages/ReportsPage";
import { DailyAttendanceReportPage } from "./ui/pages/DailyAttendanceReportPage";
import { AuditPage } from "./ui/pages/AuditPage";
import { SupportPage } from "./ui/pages/SupportPage";
import { ProfilePage } from "./ui/pages/ProfilePage";

export const router = createBrowserRouter([
  { path: "/", element: <DashboardPage /> },
  { path: "/login", element: <LoginPage /> },
  { path: "/forgot-password", element: <ForgotPasswordPage /> },
  { path: "/reset-password", element: <ResetPasswordPage /> },
  { path: "/select-company", element: <CompanySelectPage /> },

  { path: "/platform/companies", element: <PlatformCompaniesPage /> },
  { path: "/platform/users", element: <PlatformUsersPage /> },
  { path: "/org", element: <OrgPage /> },
  { path: "/staff", element: <StaffPage /> },
  { path: "/attendance", element: <AttendancePage /> },
  { path: "/audit", element: <AuditPage /> },
  { path: "/reports", element: <ReportsPage /> },
  { path: "/reports/daily-attendance", element: <DailyAttendanceReportPage /> },
  { path: "/support", element: <SupportPage /> },
  { path: "/profile", element: <ProfilePage /> }
]);

