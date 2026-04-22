-- Phase 4 / Migration 009: Platform company management procedures

begin;

create or replace function AMS_fn_is_platform_super_admin(p_user_id uuid)
returns boolean
language sql
stable
as $$
  select coalesce((select u.is_platform_super_admin from AMS_user u where u.id = p_user_id), false);
$$;

create or replace function AMS_fn_user_has_permission(
  p_user_id uuid,
  p_company_id uuid,
  p_permission_code text
)
returns boolean
language sql
stable
as $$
  select
    AMS_fn_is_platform_super_admin(p_user_id)
    or exists (
      select 1
      from AMS_fn_get_user_permission_codes(p_user_id, p_company_id) t
      where t.permission_code = p_permission_code
    );
$$;

create or replace function AMS_sp_platform_company_create(
  p_access_token text,
  p_code text,
  p_name text,
  p_timezone text default 'Asia/Kolkata'
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_sess record;
  v_user_id uuid;
  v_company_id uuid := gen_random_uuid();
begin
  select * into v_sess from AMS_fn_validate_user_session(p_access_token) limit 1;
  if not found then raise exception 'invalid_session'; end if;
  v_user_id := v_sess.user_id;

  if not AMS_fn_user_has_permission(v_user_id, coalesce(v_sess.company_id, v_company_id), 'PLATFORM_COMPANY_WRITE') then
    raise exception 'forbidden';
  end if;

  if p_code is null or length(trim(p_code)) < 2 then raise exception 'company_code_required'; end if;
  if p_name is null or length(trim(p_name)) < 2 then raise exception 'company_name_required'; end if;

  insert into AMS_company (id, code, name, is_active, created_at, updated_at, created_by, updated_by)
  values (v_company_id, upper(trim(p_code)), trim(p_name), true, v_now, v_now, v_user_id, v_user_id);

  insert into AMS_company_settings (id, AMS_company_id, timezone, is_active, created_at, updated_at, created_by, updated_by)
  values (gen_random_uuid(), v_company_id, coalesce(nullif(trim(p_timezone), ''), 'Asia/Kolkata'), true, v_now, v_now, v_user_id, v_user_id);

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (
    gen_random_uuid(),
    v_company_id,
    v_user_id,
    'PLATFORM_COMPANY_CREATE',
    'AMS_company',
    v_company_id,
    jsonb_build_object('code', upper(trim(p_code)), 'name', trim(p_name)),
    v_now, v_now, v_now, v_user_id, v_user_id
  );

  return jsonb_build_object('id', v_company_id, 'code', upper(trim(p_code)), 'name', trim(p_name));
end;
$$;

create or replace function AMS_sp_platform_company_update(
  p_access_token text,
  p_company_id uuid,
  p_name text,
  p_is_active boolean
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
  select * into v_sess from AMS_fn_validate_user_session(p_access_token) limit 1;
  if not found then raise exception 'invalid_session'; end if;
  v_user_id := v_sess.user_id;

  if not AMS_fn_user_has_permission(v_user_id, coalesce(v_sess.company_id, p_company_id), 'PLATFORM_COMPANY_WRITE') then
    raise exception 'forbidden';
  end if;

  update AMS_company
    set name = coalesce(nullif(trim(p_name), ''), name),
        is_active = coalesce(p_is_active, is_active),
        updated_at = v_now,
        updated_by = v_user_id
  where id = p_company_id;

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (
    gen_random_uuid(),
    p_company_id,
    v_user_id,
    'PLATFORM_COMPANY_UPDATE',
    'AMS_company',
    p_company_id,
    jsonb_build_object('name', p_name, 'is_active', p_is_active),
    v_now, v_now, v_now, v_user_id, v_user_id
  );

  return jsonb_build_object('updated', true);
end;
$$;

commit;

