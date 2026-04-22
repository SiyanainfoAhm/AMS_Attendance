-- Hotfix: ensure AMS_fn_require_company_context exists on remote DB
-- Some environments missed migration 011; later procedures depend on this helper.

begin;

create or replace function AMS_fn_require_company_context(p_access_token text)
returns table (user_id uuid, company_id uuid)
language plpgsql
security definer
as $$
declare
  v_sess record;
begin
  select * into v_sess from AMS_fn_validate_user_session(p_access_token) limit 1;
  if not found then
    raise exception 'invalid_session';
  end if;
  if v_sess.company_id is null then
    raise exception 'company_not_selected';
  end if;

  user_id := v_sess.user_id;
  company_id := v_sess.company_id;
  return next;
end;
$$;

-- Also keep a compatibility alias for typo'd callers.
create or replace function AMS_fn_required_company_context(p_access_token text)
returns table (user_id uuid, company_id uuid)
language sql
security definer
as $$
  select * from AMS_fn_require_company_context(p_access_token);
$$;

commit;

