-- Platform user update (display name, email, password, PSA flag)
-- Used by admin-web "Edit user" modal through Edge function `platform-users?action=update`.

begin;

create or replace function AMS_sp_platform_user_update(
  p_access_token text,
  p_user_id uuid,
  p_display_name text default null,
  p_email text default null,
  p_password text default null,
  p_is_platform_super_admin boolean default null,
  p_is_active boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_sess record;
  v_actor uuid;
begin
  select * into v_sess from AMS_fn_validate_user_session(p_access_token) limit 1;
  if not found then raise exception 'invalid_session'; end if;
  v_actor := v_sess.user_id;

  if not AMS_fn_user_has_permission(v_actor, coalesce(v_sess.company_id, p_user_id), 'PLATFORM_USER_WRITE') then
    raise exception 'forbidden';
  end if;

  if p_user_id is null then raise exception 'invalid_body'; end if;

  if p_email is not null and position('@' in p_email) <= 1 then raise exception 'email_required'; end if;
  if p_display_name is not null and length(trim(p_display_name)) < 2 then raise exception 'display_name_required'; end if;
  if p_password is not null and length(p_password) < 8 then raise exception 'weak_password'; end if;

  update AMS_user
    set display_name = coalesce(nullif(trim(p_display_name), ''), display_name),
        email = case when p_email is null then email else lower(nullif(trim(p_email), '')) end,
        password_hash = case when p_password is null then password_hash else AMS_fn_password_hash_bcrypt(p_password) end,
        password_algo = case when p_password is null then password_algo else 'bcrypt' end,
        is_platform_super_admin = coalesce(p_is_platform_super_admin, is_platform_super_admin),
        is_active = coalesce(p_is_active, is_active),
        updated_at = v_now,
        updated_by = v_actor
  where id = p_user_id;

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (
    gen_random_uuid(),
    null,
    v_actor,
    'PLATFORM_USER_UPDATE',
    'AMS_user',
    p_user_id,
    jsonb_build_object(
      'display_name', p_display_name,
      'email', p_email,
      'is_platform_super_admin', p_is_platform_super_admin,
      'is_active', p_is_active,
      'password_changed', (p_password is not null)
    ),
    v_now, v_now, v_now, v_actor, v_actor
  );

  return jsonb_build_object('updated', true);
end;
$$;

grant execute on function public.ams_sp_platform_user_update(text, uuid, text, text, text, boolean, boolean) to anon;
grant execute on function public.ams_sp_platform_user_update(text, uuid, text, text, text, boolean, boolean) to authenticated;
grant execute on function public.ams_sp_platform_user_update(text, uuid, text, text, text, boolean, boolean) to service_role;

notify pgrst, 'reload schema';

commit;

