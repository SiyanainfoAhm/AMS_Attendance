-- Seed (optional): create a demo platform super admin + demo company
-- IMPORTANT: replace email/password before production use.

begin;

-- Demo company
insert into AMS_company (id, code, name, is_active)
values (gen_random_uuid(), 'DEMO', 'Demo Company', true)
on conflict (code) do nothing;

-- Demo platform super admin user
insert into AMS_user (id, display_name, email, password_hash, password_algo, is_active, is_platform_super_admin)
values (
  gen_random_uuid(),
  'Platform Admin',
  'admin@demo.local',
  AMS_fn_password_hash_bcrypt('ChangeMe@123'),
  'bcrypt',
  true,
  true
)
on conflict do nothing;

-- Map demo admin to demo company (so company selection works)
insert into AMS_user_company_map (id, AMS_user_id, AMS_company_id, is_active)
select
  gen_random_uuid(),
  u.id,
  c.id,
  true
from AMS_user u
join AMS_company c on c.code = 'DEMO'
where lower(u.email) = lower('admin@demo.local')
on conflict (AMS_user_id, AMS_company_id) do nothing;

commit;

