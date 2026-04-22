-- Hotfix: branch org RPCs for PostgREST + Edge `company-org`
-- PostgREST resolves RPC args in an order that did not match (text, uuid, text, text) for create;
-- remote schema cache error referenced (p_access_token, p_code, p_name, p_zone_id) i.e. (text, text, text, uuid).

begin;

drop function if exists public.ams_sp_company_branch_create(text, uuid, text, text);
drop function if exists public.ams_sp_company_branch_update(text, uuid, uuid, text, boolean);

create or replace function AMS_sp_company_branch_create(
  p_access_token text,
  p_code text,
  p_name text,
  p_zone_id uuid default null
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
  p_is_active boolean default null,
  p_name text default null,
  p_zone_id uuid default null
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

commit;
