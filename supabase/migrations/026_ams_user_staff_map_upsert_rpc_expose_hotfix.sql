-- Hotfix: expose user<->staff mapping upsert RPC for PostgREST schema cache
-- Ensures function exists in public with search_path, grants, and schema reload.

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
      and p.proname = 'ams_sp_company_user_staff_map_upsert'
  loop
    execute 'drop function if exists ' || fn || ' cascade';
  end loop;
end $$;

create or replace function AMS_sp_company_user_staff_map_upsert(
  p_access_token text,
  p_user_id uuid,
  p_staff_id uuid,
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

  if p_user_id is null or p_staff_id is null then
    raise exception 'invalid_body';
  end if;

  if not exists (
    select 1
    from AMS_user_company_map ucm
    join AMS_company c on c.id = ucm.AMS_company_id
    where ucm.AMS_user_id = p_user_id
      and ucm.AMS_company_id = v_ctx.company_id
      and ucm.is_active = true
      and c.is_active = true
  ) then
    raise exception 'user_not_in_company';
  end if;

  if not exists (
    select 1
    from AMS_staff s
    where s.id = p_staff_id
      and s.AMS_company_id = v_ctx.company_id
      and s.is_active = true
  ) then
    raise exception 'staff_not_found';
  end if;

  insert into AMS_user_staff_map (
    id, AMS_company_id, AMS_user_id, AMS_staff_id, is_active,
    created_at, updated_at, created_by, updated_by
  )
  values (
    gen_random_uuid(), v_ctx.company_id, p_user_id, p_staff_id, coalesce(p_is_active, true),
    v_now, v_now, v_ctx.user_id, v_ctx.user_id
  )
  on conflict (ams_user_id, ams_company_id) do update
  set
    ams_staff_id = excluded.ams_staff_id,
    is_active = excluded.is_active,
    updated_at = v_now,
    updated_by = v_ctx.user_id;

  insert into AMS_audit_log (
    id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json,
    occurred_at, created_at, updated_at, created_by, updated_by
  )
  values (
    gen_random_uuid(), v_ctx.company_id, v_ctx.user_id, 'COMPANY_USER_STAFF_MAP_UPSERT',
    'AMS_user_staff_map', p_user_id,
    jsonb_build_object('mapped_user_id', p_user_id, 'staff_id', p_staff_id, 'is_active', coalesce(p_is_active, true)),
    v_now, v_now, v_now, v_ctx.user_id, v_ctx.user_id
  );

  return jsonb_build_object('user_id', p_user_id, 'staff_id', p_staff_id);
end;
$$;

grant execute on function public.ams_sp_company_user_staff_map_upsert(text, uuid, uuid, boolean) to anon;
grant execute on function public.ams_sp_company_user_staff_map_upsert(text, uuid, uuid, boolean) to authenticated;
grant execute on function public.ams_sp_company_user_staff_map_upsert(text, uuid, uuid, boolean) to service_role;

notify pgrst, 'reload schema';

commit;
