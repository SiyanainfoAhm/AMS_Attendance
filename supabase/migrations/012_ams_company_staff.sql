-- Phase 4 / Migration 012: Company staff CRUD + station mapping + document metadata

begin;

create or replace function AMS_sp_company_staff_create(
  p_access_token text,
  p_staff_code text,
  p_full_name text,
  p_mobile text default null,
  p_email text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_ctx record;
  v_id uuid := gen_random_uuid();
begin
  select * into v_ctx from AMS_fn_require_company_context(p_access_token) limit 1;
  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_STAFF_WRITE') then
    raise exception 'forbidden';
  end if;

  if p_staff_code is null or length(trim(p_staff_code)) < 2 then raise exception 'staff_code_required'; end if;
  if p_full_name is null or length(trim(p_full_name)) < 2 then raise exception 'full_name_required'; end if;

  insert into AMS_staff (
    id, AMS_company_id, staff_code, full_name, mobile, email, status, is_active,
    created_at, updated_at, created_by, updated_by
  ) values (
    v_id, v_ctx.company_id, upper(trim(p_staff_code)), trim(p_full_name), nullif(trim(p_mobile), ''), nullif(lower(trim(p_email)), ''),
    'active', true,
    v_now, v_now, v_ctx.user_id, v_ctx.user_id
  );

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (gen_random_uuid(), v_ctx.company_id, v_ctx.user_id, 'COMPANY_STAFF_CREATE', 'AMS_staff', v_id,
          jsonb_build_object('staff_code', upper(trim(p_staff_code)), 'full_name', trim(p_full_name)), v_now, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function AMS_sp_company_staff_update(
  p_access_token text,
  p_staff_id uuid,
  p_full_name text default null,
  p_mobile text default null,
  p_email text default null,
  p_status text default null,
  p_is_active boolean default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_ctx record;
  v_old_status text;
  v_new_status text;
begin
  select * into v_ctx from AMS_fn_require_company_context(p_access_token) limit 1;
  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_STAFF_WRITE') then
    raise exception 'forbidden';
  end if;

  select s.status into v_old_status from AMS_staff s
  where s.id = p_staff_id and s.AMS_company_id = v_ctx.company_id
  limit 1;

  update AMS_staff
    set full_name = coalesce(nullif(trim(p_full_name), ''), full_name),
        mobile = coalesce(nullif(trim(p_mobile), ''), mobile),
        email = coalesce(nullif(lower(trim(p_email)), ''), email),
        status = coalesce(nullif(trim(p_status), ''), status),
        is_active = coalesce(p_is_active, is_active),
        updated_at = v_now,
        updated_by = v_ctx.user_id
  where id = p_staff_id and AMS_company_id = v_ctx.company_id;

  select s.status into v_new_status from AMS_staff s
  where s.id = p_staff_id and s.AMS_company_id = v_ctx.company_id
  limit 1;

  if v_old_status is distinct from v_new_status then
    insert into AMS_staff_status_history (id, AMS_company_id, AMS_staff_id, from_status, to_status, reason, changed_at, changed_by, created_at, updated_at, created_by, updated_by)
    values (gen_random_uuid(), v_ctx.company_id, p_staff_id, v_old_status, v_new_status, null, v_now, v_ctx.user_id, v_now, v_now, v_ctx.user_id, v_ctx.user_id);
  end if;

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (gen_random_uuid(), v_ctx.company_id, v_ctx.user_id, 'COMPANY_STAFF_UPDATE', 'AMS_staff', p_staff_id,
          jsonb_build_object('full_name', p_full_name, 'mobile', p_mobile, 'email', p_email, 'status', p_status, 'is_active', p_is_active),
          v_now, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  return jsonb_build_object('updated', true);
end;
$$;

create or replace function AMS_sp_company_staff_map_station(
  p_access_token text,
  p_staff_id uuid,
  p_station_id uuid,
  p_is_primary boolean default false,
  p_is_active boolean default true
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_ctx record;
begin
  select * into v_ctx from AMS_fn_require_company_context(p_access_token) limit 1;
  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_STAFF_WRITE') then
    raise exception 'forbidden';
  end if;

  insert into AMS_staff_station_map (id, AMS_company_id, AMS_staff_id, AMS_station_id, is_primary, is_active, created_at, updated_at, created_by, updated_by)
  values (gen_random_uuid(), v_ctx.company_id, p_staff_id, p_station_id, coalesce(p_is_primary,false), coalesce(p_is_active,true), v_now, v_now, v_ctx.user_id, v_ctx.user_id)
  on conflict (AMS_staff_id, AMS_station_id) do update
    set is_primary = excluded.is_primary,
        is_active = excluded.is_active,
        updated_at = v_now,
        updated_by = v_ctx.user_id;

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (gen_random_uuid(), v_ctx.company_id, v_ctx.user_id, 'COMPANY_STAFF_MAP_STATION', 'AMS_staff_station_map', p_staff_id,
          jsonb_build_object('staff_id', p_staff_id, 'station_id', p_station_id, 'is_primary', p_is_primary, 'is_active', p_is_active),
          v_now, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  return jsonb_build_object('mapped', true);
end;
$$;

create or replace function AMS_sp_company_staff_add_document(
  p_access_token text,
  p_staff_id uuid,
  p_document_type text,
  p_document_number text default null,
  p_storage_bucket text default null,
  p_storage_path text default null,
  p_issued_at date default null,
  p_expires_at date default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_ctx record;
  v_id uuid := gen_random_uuid();
begin
  select * into v_ctx from AMS_fn_require_company_context(p_access_token) limit 1;
  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_STAFF_WRITE') then
    raise exception 'forbidden';
  end if;
  if p_document_type is null or length(trim(p_document_type)) = 0 then raise exception 'document_type_required'; end if;

  insert into AMS_staff_document (
    id, AMS_company_id, AMS_staff_id, document_type, document_number, storage_bucket, storage_path,
    status, issued_at, expires_at, created_at, updated_at, created_by, updated_by
  ) values (
    v_id, v_ctx.company_id, p_staff_id, trim(p_document_type), nullif(trim(p_document_number), ''),
    nullif(trim(p_storage_bucket), ''), nullif(trim(p_storage_path), ''),
    'pending', p_issued_at, p_expires_at, v_now, v_now, v_ctx.user_id, v_ctx.user_id
  );

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (gen_random_uuid(), v_ctx.company_id, v_ctx.user_id, 'COMPANY_STAFF_ADD_DOCUMENT', 'AMS_staff_document', v_id,
          jsonb_build_object('staff_id', p_staff_id, 'document_type', p_document_type, 'storage_path', p_storage_path),
          v_now, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  return jsonb_build_object('id', v_id);
end;
$$;

commit;

