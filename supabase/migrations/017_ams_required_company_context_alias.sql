-- Hotfix: some remote objects may reference AMS_fn_required_company_context (typo)
-- Canonical helper is AMS_fn_require_company_context (migration 011).

begin;

create or replace function AMS_fn_required_company_context(p_access_token text)
returns table (user_id uuid, company_id uuid)
language sql
security definer
as $$
  select * from AMS_fn_require_company_context(p_access_token);
$$;

commit;

