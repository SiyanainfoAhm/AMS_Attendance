## Architecture (Phase 1)

### Principle: Supabase is backend platform only
- **Use**: PostgreSQL, Storage, Realtime (optional), Edge Functions
- **Do not use**: Supabase Authentication

### API Gateway
All clients (React/Flutter) call **Edge Functions** only.
Edge Functions validate:
- `AMS_user_session` (custom session model)
- `AMS_company_id` context + membership checks
- permission checks (RBAC)

Then Edge Functions call Postgres/Storage using the **Service Role key** server-side only.

### Multi-tenancy
- Shared schema multi-tenant model
- Every business/transactional table has `AMS_company_id`
- Every query path validates company access
- No cross-company joins without explicit platform-super-admin intent

### Data contracts
Put shared DTOs and validation schemas in `packages/shared-contracts`.

