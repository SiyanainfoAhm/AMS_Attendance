-- Creates a single platform superadmin login + maps to a demo company.
-- Safe to re-run (idempotent).
--
-- Default credentials (change after first login):
--   email:    admin@ams.local
--   password: ChangeMe@123

begin;

-- Ensure a company exists for company-selection flows.
insert into AMS_company (id, code, name, is_active)
values (gen_random_uuid(), 'DEMO', 'Demo Company', true)
on conflict (code) do nothing;

-- Create superadmin user (platform-wide).
insert into AMS_user (id, display_name, email, password_hash, password_algo, is_active, is_platform_super_admin)
values (
  gen_random_uuid(),
  'Platform Super Admin',
  lower('admin@ams.local'),
  AMS_fn_password_hash_bcrypt('ChangeMe@123'),
  'bcrypt',
  true,
  true
)
on conflict ((lower(email))) where email is not null do nothing;

-- Map admin to DEMO company so select-company works.
insert into AMS_user_company_map (id, AMS_user_id, AMS_company_id, is_active)
select
  gen_random_uuid(),
  u.id,
  c.id,
  true
from AMS_user u
join AMS_company c on c.code = 'DEMO'
where lower(u.email) = lower('admin@ams.local')
on conflict (AMS_user_id, AMS_company_id) do nothing;

commit;

