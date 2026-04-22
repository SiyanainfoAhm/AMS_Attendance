-- Phase 4 / Migration 008: RBAC helpers for roles + permissions

begin;

create or replace function AMS_fn_get_user_roles(
  p_user_id uuid,
  p_company_id uuid
)
returns table (
  role_id uuid,
  role_code text,
  role_name text
)
language sql
stable
as $$
  select
    r.id as role_id,
    r.code as role_code,
    r.name as role_name
  from AMS_user_role_map urm
  join AMS_role r on r.id = urm.AMS_role_id
  where urm.AMS_user_id = p_user_id
    and urm.is_active = true
    and r.is_active = true
    and (
      -- platform roles apply everywhere
      (r.AMS_company_id is null)
      or
      -- company roles apply to that company
      (r.AMS_company_id = p_company_id)
    )
    and (
      urm.AMS_company_id is null
      or urm.AMS_company_id = p_company_id
    )
  order by r.is_platform_role desc, r.code;
$$;

create or replace function AMS_fn_get_user_permission_codes(
  p_user_id uuid,
  p_company_id uuid
)
returns table (
  permission_code text
)
language sql
stable
as $$
  select distinct p.code as permission_code
  from AMS_user_role_map urm
  join AMS_role r on r.id = urm.AMS_role_id
  join AMS_role_permission_map rpm on rpm.AMS_role_id = r.id
  join AMS_permission p on p.id = rpm.AMS_permission_id
  where urm.AMS_user_id = p_user_id
    and urm.is_active = true
    and r.is_active = true
    and p.is_active = true
    and (
      (r.AMS_company_id is null)
      or (r.AMS_company_id = p_company_id)
    )
    and (
      urm.AMS_company_id is null
      or urm.AMS_company_id = p_company_id
    )
  order by p.code;
$$;

commit;

