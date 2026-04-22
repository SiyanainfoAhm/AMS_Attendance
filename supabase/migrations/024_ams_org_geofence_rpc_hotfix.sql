-- Geofence: valid PG parameter order for CREATE (011 had optional station before required code/name).
-- Update: allow editing circle center + radius (optional params).

begin;

do $$
declare
  fn text;
begin
  for fn in
    select format('%I.%I(%s)', n.nspname, p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid))
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('ams_sp_company_geofence_create', 'ams_sp_company_geofence_update')
  loop
    execute 'drop function if exists ' || fn || ' cascade';
  end loop;
end $$;

create or replace function AMS_sp_company_geofence_create(
  p_access_token text,
  p_code text,
  p_name text,
  p_geofence_type text default 'circle',
  p_station_id uuid default null,
  p_center_lat double precision default null,
  p_center_lng double precision default null,
  p_radius_m numeric default null,
  p_polygon_json jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
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
  p_is_active boolean default null,
  p_center_lat double precision default null,
  p_center_lng double precision default null,
  p_radius_m numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
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
        center_lat = coalesce(p_center_lat, center_lat),
        center_lng = coalesce(p_center_lng, center_lng),
        radius_m = coalesce(p_radius_m, radius_m),
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

grant execute on function public.ams_sp_company_geofence_create(text, text, text, text, uuid, double precision, double precision, numeric, jsonb) to anon;
grant execute on function public.ams_sp_company_geofence_create(text, text, text, text, uuid, double precision, double precision, numeric, jsonb) to authenticated;
grant execute on function public.ams_sp_company_geofence_create(text, text, text, text, uuid, double precision, double precision, numeric, jsonb) to service_role;

grant execute on function public.ams_sp_company_geofence_update(text, uuid, uuid, text, boolean, double precision, double precision, numeric) to anon;
grant execute on function public.ams_sp_company_geofence_update(text, uuid, uuid, text, boolean, double precision, double precision, numeric) to authenticated;
grant execute on function public.ams_sp_company_geofence_update(text, uuid, uuid, text, boolean, double precision, double precision, numeric) to service_role;

notify pgrst, 'reload schema';

commit;
