-- Phase 3 / Migration 007: Company selection (bind session to AMS_company_id)

begin;

create or replace function AMS_sp_select_company(
  p_access_token text,
  p_company_id uuid
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_sess record;
  v_user_id uuid;
begin
  if p_company_id is null then
    raise exception 'company_id_required';
  end if;

  select * into v_sess from AMS_fn_validate_user_session(p_access_token) limit 1;
  if not found then
    raise exception 'invalid_session';
  end if;

  v_user_id := v_sess.user_id;

  if not AMS_fn_validate_user_company_access(v_user_id, p_company_id) then
    raise exception 'company_access_denied';
  end if;

  update AMS_user_session
    set AMS_company_id = p_company_id,
        updated_at = v_now
  where id = v_sess.session_id;

  return jsonb_build_object('selected', true, 'company_id', p_company_id);
end;
$$;

commit;

