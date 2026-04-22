-- Phase 4 / Migration 011: Company org CRUD procedures (zone/branch/station/geofence)

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
  if not found then raise exception 'invalid_session'; end if;
  if v_sess.company_id is null then raise exception 'company_not_selected'; end if;
  user_id := v_sess.user_id;
  company_id := v_sess.company_id;
  return next;
end;
$$;

-- -----------------------------------------------------------------------------
-- Zone
-- -----------------------------------------------------------------------------

create or replace function AMS_sp_company_zone_create(
  p_access_token text,
  p_code text,
  p_name text,
  p_description text default null
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
  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ORG_WRITE') then
    raise exception 'forbidden';
  end if;
  if p_code is null or length(trim(p_code)) < 2 then raise exception 'zone_code_required'; end if;
  if p_name is null or length(trim(p_name)) < 2 then raise exception 'zone_name_required'; end if;

  insert into AMS_zone (id, AMS_company_id, code, name, description, is_active, created_at, updated_at, created_by, updated_by)
  values (v_id, v_ctx.company_id, upper(trim(p_code)), trim(p_name), p_description, true, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (gen_random_uuid(), v_ctx.company_id, v_ctx.user_id, 'COMPANY_ZONE_CREATE', 'AMS_zone', v_id,
          jsonb_build_object('code', upper(trim(p_code)), 'name', trim(p_name)), v_now, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function AMS_sp_company_zone_update(
  p_access_token text,
  p_zone_id uuid,
  p_name text default null,
  p_description text default null,
  p_is_active boolean default null
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
  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ORG_WRITE') then
    raise exception 'forbidden';
  end if;

  update AMS_zone
    set name = coalesce(nullif(trim(p_name), ''), name),
        description = coalesce(p_description, description),
        is_active = coalesce(p_is_active, is_active),
        updated_at = v_now,
        updated_by = v_ctx.user_id
  where id = p_zone_id and AMS_company_id = v_ctx.company_id;

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (gen_random_uuid(), v_ctx.company_id, v_ctx.user_id, 'COMPANY_ZONE_UPDATE', 'AMS_zone', p_zone_id,
          jsonb_build_object('name', p_name, 'is_active', p_is_active), v_now, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  return jsonb_build_object('updated', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- Branch
-- -----------------------------------------------------------------------------

create or replace function AMS_sp_company_branch_create(
  p_access_token text,
  p_zone_id uuid default null,
  p_code text,
  p_name text
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
  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ORG_WRITE') then
    raise exception 'forbidden';
  end if;
  if p_code is null or length(trim(p_code)) < 2 then raise exception 'branch_code_required'; end if;
  if p_name is null or length(trim(p_name)) < 2 then raise exception 'branch_name_required'; end if;

  insert into AMS_branch (id, AMS_company_id, AMS_zone_id, code, name, is_active, created_at, updated_at, created_by, updated_by)
  values (v_id, v_ctx.company_id, p_zone_id, upper(trim(p_code)), trim(p_name), true, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (gen_random_uuid(), v_ctx.company_id, v_ctx.user_id, 'COMPANY_BRANCH_CREATE', 'AMS_branch', v_id,
          jsonb_build_object('code', upper(trim(p_code)), 'name', trim(p_name), 'zone_id', p_zone_id), v_now, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function AMS_sp_company_branch_update(
  p_access_token text,
  p_branch_id uuid,
  p_zone_id uuid default null,
  p_name text default null,
  p_is_active boolean default null
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
  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ORG_WRITE') then
    raise exception 'forbidden';
  end if;

  update AMS_branch
    set AMS_zone_id = coalesce(p_zone_id, AMS_zone_id),
        name = coalesce(nullif(trim(p_name), ''), name),
        is_active = coalesce(p_is_active, is_active),
        updated_at = v_now,
        updated_by = v_ctx.user_id
  where id = p_branch_id and AMS_company_id = v_ctx.company_id;

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (gen_random_uuid(), v_ctx.company_id, v_ctx.user_id, 'COMPANY_BRANCH_UPDATE', 'AMS_branch', p_branch_id,
          jsonb_build_object('name', p_name, 'zone_id', p_zone_id, 'is_active', p_is_active), v_now, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  return jsonb_build_object('updated', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- Station
-- -----------------------------------------------------------------------------

create or replace function AMS_sp_company_station_create(
  p_access_token text,
  p_zone_id uuid default null,
  p_branch_id uuid default null,
  p_code text,
  p_name text
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
  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ORG_WRITE') then
    raise exception 'forbidden';
  end if;
  if p_code is null or length(trim(p_code)) < 2 then raise exception 'station_code_required'; end if;
  if p_name is null or length(trim(p_name)) < 2 then raise exception 'station_name_required'; end if;

  insert into AMS_station (id, AMS_company_id, AMS_zone_id, AMS_branch_id, code, name, is_active, created_at, updated_at, created_by, updated_by)
  values (v_id, v_ctx.company_id, p_zone_id, p_branch_id, upper(trim(p_code)), trim(p_name), true, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (gen_random_uuid(), v_ctx.company_id, v_ctx.user_id, 'COMPANY_STATION_CREATE', 'AMS_station', v_id,
          jsonb_build_object('code', upper(trim(p_code)), 'name', trim(p_name), 'zone_id', p_zone_id, 'branch_id', p_branch_id),
          v_now, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function AMS_sp_company_station_update(
  p_access_token text,
  p_station_id uuid,
  p_zone_id uuid default null,
  p_branch_id uuid default null,
  p_name text default null,
  p_is_active boolean default null
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
  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ORG_WRITE') then
    raise exception 'forbidden';
  end if;

  update AMS_station
    set AMS_zone_id = coalesce(p_zone_id, AMS_zone_id),
        AMS_branch_id = coalesce(p_branch_id, AMS_branch_id),
        name = coalesce(nullif(trim(p_name), ''), name),
        is_active = coalesce(p_is_active, is_active),
        updated_at = v_now,
        updated_by = v_ctx.user_id
  where id = p_station_id and AMS_company_id = v_ctx.company_id;

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (gen_random_uuid(), v_ctx.company_id, v_ctx.user_id, 'COMPANY_STATION_UPDATE', 'AMS_station', p_station_id,
          jsonb_build_object('name', p_name, 'zone_id', p_zone_id, 'branch_id', p_branch_id, 'is_active', p_is_active),
          v_now, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  return jsonb_build_object('updated', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- Geofence
-- -----------------------------------------------------------------------------

create or replace function AMS_sp_company_geofence_create(
  p_access_token text,
  p_station_id uuid default null,
  p_code text,
  p_name text,
  p_geofence_type text default 'circle',
  p_center_lat double precision default null,
  p_center_lng double precision default null,
  p_radius_m numeric default null,
  p_polygon_json jsonb default '[]'::jsonb
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
  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ORG_WRITE') then
    raise exception 'forbidden';
  end if;
  if p_code is null or length(trim(p_code)) < 2 then raise exception 'geofence_code_required'; end if;
  if p_name is null or length(trim(p_name)) < 2 then raise exception 'geofence_name_required'; end if;

  insert into AMS_geofence (
    id, AMS_company_id, AMS_station_id, code, name, geofence_type,
    center_lat, center_lng, radius_m, polygon_json,
    is_active, created_at, updated_at, created_by, updated_by
  ) values (
    v_id, v_ctx.company_id, p_station_id, upper(trim(p_code)), trim(p_name), coalesce(p_geofence_type, 'circle'),
    p_center_lat, p_center_lng, p_radius_m, coalesce(p_polygon_json, '[]'::jsonb),
    true, v_now, v_now, v_ctx.user_id, v_ctx.user_id
  );

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (gen_random_uuid(), v_ctx.company_id, v_ctx.user_id, 'COMPANY_GEOFENCE_CREATE', 'AMS_geofence', v_id,
          jsonb_build_object('code', upper(trim(p_code)), 'name', trim(p_name), 'station_id', p_station_id, 'type', p_geofence_type),
          v_now, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function AMS_sp_company_geofence_update(
  p_access_token text,
  p_geofence_id uuid,
  p_station_id uuid default null,
  p_name text default null,
  p_is_active boolean default null
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
  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ORG_WRITE') then
    raise exception 'forbidden';
  end if;

  update AMS_geofence
    set AMS_station_id = coalesce(p_station_id, AMS_station_id),
        name = coalesce(nullif(trim(p_name), ''), name),
        is_active = coalesce(p_is_active, is_active),
        updated_at = v_now,
        updated_by = v_ctx.user_id
  where id = p_geofence_id and AMS_company_id = v_ctx.company_id;

  insert into AMS_audit_log (id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json, occurred_at, created_at, updated_at, created_by, updated_by)
  values (gen_random_uuid(), v_ctx.company_id, v_ctx.user_id, 'COMPANY_GEOFENCE_UPDATE', 'AMS_geofence', p_geofence_id,
          jsonb_build_object('name', p_name, 'station_id', p_station_id, 'is_active', p_is_active),
          v_now, v_now, v_now, v_ctx.user_id, v_ctx.user_id);

  return jsonb_build_object('updated', true);
end;
$$;

commit;

