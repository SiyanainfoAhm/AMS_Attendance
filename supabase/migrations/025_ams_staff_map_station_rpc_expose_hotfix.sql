-- Hotfix: expose staff->station mapping RPC for PostgREST schema cache
-- Some envs have drift; ensure function exists in public with search_path, grants, and schema reload.

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
      and p.proname = 'ams_sp_company_staff_map_station'
  loop
    execute 'drop function if exists ' || fn || ' cascade';
  end loop;
end $$;

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
set search_path = public
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

grant execute on function public.ams_sp_company_staff_map_station(text, uuid, uuid, boolean, boolean) to anon;
grant execute on function public.ams_sp_company_staff_map_station(text, uuid, uuid, boolean, boolean) to authenticated;
grant execute on function public.ams_sp_company_staff_map_station(text, uuid, uuid, boolean, boolean) to service_role;

notify pgrst, 'reload schema';

commit;
