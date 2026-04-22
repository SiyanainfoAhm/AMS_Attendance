## AMS (Attendance Management System)

Production-ready, multi-tenant Attendance Management System.

### Apps
- `apps/admin-web`: React + TypeScript web admin
- `apps/mobile-staff`: Flutter staff mobile app
- `apps/kiosk`: Flutter kiosk app (**on hold**)

### Run admin web (Windows / npm)
From repo root:

```bash
npm install --prefix apps/admin-web
npm run dev:admin
```

### Backend (Supabase only)
- `supabase/migrations`: PostgreSQL schema/migrations (all DB objects `AMS_*`)
- `supabase/functions`: Supabase Edge Functions (API gateway; no Supabase Auth)
- `supabase/seed`: seed SQL for demo data

### Non-negotiables
- Supabase Auth is **not used**
- Custom auth tables: `AMS_user`, `AMS_user_session`
- Multi-tenancy: all business tables include `AMS_company_id`
- Every DB object uses `AMS_` prefix

