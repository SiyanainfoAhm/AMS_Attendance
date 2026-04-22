-- Phase 4 / Migration 010: Platform user management procedures

begin;

create or replace function AMS_sp_platform_user_create(
  p_access_token text,
  p_display_name text,
  p_email text,
  p_password text,
  p_is_platform_super_admin boolean default false
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_sess record;
  v_actor uuid;
  v_user_id uuid := gen_random_uuid();
begin
  select * into v_sess from AMS_fn_validate_user_session(p_access_token) limit 1;
  if not found then raise exception 'invalid_session'; end if;
  v_actor := v_sess.user_id;

  if not AMS_fn_user_has_permission(v_actor, coalesce(v_sess.company_id, v_user_id), 'PLATFORM_USER_WRITE') then
    raise exception 'forbidden';
  end if;

  if p_email is null or position('@' in p_email) <= 1 then raise exception 'email_required'; end if;
  if p_password is null or length(p_password) < 8 then raise exception 'weak_password'; end if;
  if p_display_name is null or length(trim(p_display_name)) < 2 then raise exception 'display_name_required'; end if;

  insert into AMS_user (
    id, display_name, email, password_hash, password_algo, is_active, is_platform_super_admin,
    created_at, updated_at, created_by, updated_by
  ) values (
    v_user_id,
    trim(p_display_name),
    lower(trim(p_email)),
    AMS_fn_password_hash_bcrypt(p_password),
    'bcrypt',
    true,
    coalesce(p_is_platform_super_admin, false),
    v_now, v_now, v_actor, v_actor
  );

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (
    gen_random_uuid(),
    null,
    v_actor,
    'PLATFORM_USER_CREATE',
    'AMS_user',
    v_user_id,
    jsonb_build_object('email', lower(trim(p_email)), 'display_name', trim(p_display_name)),
    v_now, v_now, v_now, v_actor, v_actor
  );

  return jsonb_build_object('id', v_user_id, 'email', lower(trim(p_email)), 'display_name', trim(p_display_name));
end;
$$;

create or replace function AMS_sp_platform_user_set_active(
  p_access_token text,
  p_user_id uuid,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
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

  update AMS_user
    set is_active = coalesce(p_is_active, is_active),
        updated_at = v_now,
        updated_by = v_actor
  where id = p_user_id;

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (
    gen_random_uuid(),
    null,
    v_actor,
    'PLATFORM_USER_SET_ACTIVE',
    'AMS_user',
    p_user_id,
    jsonb_build_object('is_active', p_is_active),
    v_now, v_now, v_now, v_actor, v_actor
  );

  return jsonb_build_object('updated', true);
end;
$$;

create or replace function AMS_sp_platform_user_map_company(
  p_access_token text,
  p_user_id uuid,
  p_company_id uuid,
  p_is_active boolean default true
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_sess record;
  v_actor uuid;
begin
  select * into v_sess from AMS_fn_validate_user_session(p_access_token) limit 1;
  if not found then raise exception 'invalid_session'; end if;
  v_actor := v_sess.user_id;

  if not AMS_fn_user_has_permission(v_actor, coalesce(v_sess.company_id, p_company_id), 'PLATFORM_USER_WRITE') then
    raise exception 'forbidden';
  end if;

  insert into AMS_user_company_map (
    id, AMS_user_id, AMS_company_id, is_active,
    created_at, updated_at, created_by, updated_by
  ) values (
    gen_random_uuid(), p_user_id, p_company_id, coalesce(p_is_active, true),
    v_now, v_now, v_actor, v_actor
  )
  on conflict (AMS_user_id, AMS_company_id) do update
    set is_active = excluded.is_active,
        updated_at = v_now,
        updated_by = v_actor;

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (
    gen_random_uuid(),
    p_company_id,
    v_actor,
    'PLATFORM_USER_MAP_COMPANY',
    'AMS_user_company_map',
    p_user_id,
    jsonb_build_object('user_id', p_user_id, 'company_id', p_company_id, 'is_active', p_is_active),
    v_now, v_now, v_now, v_actor, v_actor
  );

  return jsonb_build_object('mapped', true);
end;
$$;

create or replace function AMS_sp_platform_user_assign_role(
  p_access_token text,
  p_user_id uuid,
  p_role_id uuid,
  p_company_id uuid default null,
  p_is_active boolean default true
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_sess record;
  v_actor uuid;
begin
  select * into v_sess from AMS_fn_validate_user_session(p_access_token) limit 1;
  if not found then raise exception 'invalid_session'; end if;
  v_actor := v_sess.user_id;

  if not AMS_fn_user_has_permission(v_actor, coalesce(v_sess.company_id, coalesce(p_company_id, p_user_id)), 'PLATFORM_USER_WRITE') then
    raise exception 'forbidden';
  end if;

  insert into AMS_user_role_map (
    id, AMS_user_id, AMS_role_id, AMS_company_id, is_active,
    created_at, updated_at, created_by, updated_by
  ) values (
    gen_random_uuid(), p_user_id, p_role_id, p_company_id, coalesce(p_is_active, true),
    v_now, v_now, v_actor, v_actor
  )
  on conflict (AMS_user_id, AMS_role_id, AMS_company_id) do update
    set is_active = excluded.is_active,
        updated_at = v_now,
        updated_by = v_actor;

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (
    gen_random_uuid(),
    p_company_id,
    v_actor,
    'PLATFORM_USER_ASSIGN_ROLE',
    'AMS_user_role_map',
    p_user_id,
    jsonb_build_object('user_id', p_user_id, 'role_id', p_role_id, 'company_id', p_company_id, 'is_active', p_is_active),
    v_now, v_now, v_now, v_actor, v_actor
  );

  return jsonb_build_object('assigned', true);
end;
$$;

commit;

