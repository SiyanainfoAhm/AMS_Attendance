## Supabase Edge Functions (API Gateway)

All client apps call Edge Functions. Edge Functions implement:
- custom auth (no Supabase Auth)
- tenant isolation checks (`AMS_company_id`)
- RBAC checks

`supabase/functions/_shared` is for shared helpers (request validation, session parsing, error mapping).

### Password reset

- `POST /auth-password-reset-request` — body `{ "email": "..." }`. Response always indicates success (`requested: true`) for valid input to avoid account enumeration.
- `POST /auth-password-reset-confirm` — body `{ "resetToken": "...", "newPassword": "..." }`.

For dev-only testing, set **`AMS_RETURN_RESET_TOKEN_IN_RESPONSE=true`** so the request response includes `reset_token` (useful before integrating an email provider).

