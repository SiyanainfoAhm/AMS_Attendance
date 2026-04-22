-- Hotfix: ensure org zone procedures exist on remote DB (PostgREST RPC)
-- Some environments missed migration 011 partially; Edge `company-org` calls these RPCs.

begin;

create or replace function AMS_sp_company_zone_create(
  p_access_token text,
  p_code text,
  p_name text,
  p_description text default null
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

commit;
