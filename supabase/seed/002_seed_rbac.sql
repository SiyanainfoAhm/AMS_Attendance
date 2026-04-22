-- Seed baseline RBAC (permissions, roles, mappings)
-- Safe to re-run (uses ON CONFLICT where possible).

begin;

-- -----------------------------------------------------------------------------
-- Permissions
-- -----------------------------------------------------------------------------

insert into AMS_permission (id, code, name, description, is_active)
values
  (gen_random_uuid(), 'PLATFORM_COMPANY_READ', 'Platform: Company read', 'List/view companies across platform', true),
  (gen_random_uuid(), 'PLATFORM_COMPANY_WRITE', 'Platform: Company write', 'Create/update companies across platform', true),
  (gen_random_uuid(), 'PLATFORM_USER_READ', 'Platform: User read', 'List/view users across platform', true),
  (gen_random_uuid(), 'PLATFORM_USER_WRITE', 'Platform: User write', 'Create/update users across platform', true),

  (gen_random_uuid(), 'COMPANY_SETTINGS_READ', 'Company: Settings read', 'View company settings', true),
  (gen_random_uuid(), 'COMPANY_SETTINGS_WRITE', 'Company: Settings write', 'Update company settings', true),

  (gen_random_uuid(), 'COMPANY_ORG_READ', 'Company: Org read', 'View zones/branches/stations/geofences', true),
  (gen_random_uuid(), 'COMPANY_ORG_WRITE', 'Company: Org write', 'Manage zones/branches/stations/geofences', true),

  (gen_random_uuid(), 'COMPANY_STAFF_READ', 'Company: Staff read', 'View staff and documents', true),
  (gen_random_uuid(), 'COMPANY_STAFF_WRITE', 'Company: Staff write', 'Create/update staff, onboarding, documents', true),

  (gen_random_uuid(), 'COMPANY_ATTENDANCE_READ', 'Company: Attendance read', 'View attendance logs and monitoring', true),
  (gen_random_uuid(), 'COMPANY_ATTENDANCE_WRITE', 'Company: Attendance write', 'Audit/adjust attendance where allowed', true),
  (gen_random_uuid(), 'COMPANY_ATTENDANCE_PUNCH', 'Company: Attendance punch', 'Record in/out/break punches for staff', true),

  (gen_random_uuid(), 'COMPANY_SHIFT_READ', 'Company: Shift read', 'View shifts/rosters/muster rolls', true),
  (gen_random_uuid(), 'COMPANY_SHIFT_WRITE', 'Company: Shift write', 'Manage shifts/rosters/automation', true),

  (gen_random_uuid(), 'COMPANY_DEVICE_READ', 'Company: Device read', 'View devices/kiosks health', true),
  (gen_random_uuid(), 'COMPANY_DEVICE_WRITE', 'Company: Device write', 'Register/activate devices/kiosks', true),

  (gen_random_uuid(), 'COMPANY_REPORT_READ', 'Company: Report read', 'View reports', true),
  (gen_random_uuid(), 'COMPANY_REPORT_EXPORT', 'Company: Report export', 'Export reports to XLSX/PDF', true),

  (gen_random_uuid(), 'COMPANY_SUPPORT_READ', 'Company: Support read', 'View support tickets/issues', true),
  (gen_random_uuid(), 'COMPANY_SUPPORT_WRITE', 'Company: Support write', 'Create/update/resolve tickets/issues', true),

  (gen_random_uuid(), 'COMPANY_COMPLIANCE_READ', 'Company: Compliance read', 'View compliance/doc expiry', true),
  (gen_random_uuid(), 'COMPANY_COMPLIANCE_WRITE', 'Company: Compliance write', 'Manage compliance flags/whitelist/blacklist', true),

  (gen_random_uuid(), 'STAFF_SUPPORT_TICKET', 'Staff: Support tickets (own)', 'Create support tickets and view tickets you opened', true)
on conflict (code) do update
set
  name = excluded.name,
  description = excluded.description,
  is_active = excluded.is_active;

-- -----------------------------------------------------------------------------
-- Roles
-- -----------------------------------------------------------------------------

-- Platform super admin role (global)
insert into AMS_role (id, AMS_company_id, code, name, description, is_platform_role, is_active)
values (gen_random_uuid(), null, 'PLATFORM_SUPER_ADMIN', 'Platform Super Admin', 'Full platform access', true, true)
on conflict do nothing;

-- Company roles for DEMO company (seed convenience)
insert into AMS_role (id, AMS_company_id, code, name, description, is_platform_role, is_active)
select gen_random_uuid(), c.id, x.code, x.name, x.description, false, true
from AMS_company c
cross join (values
  ('COMPANY_ADMIN', 'Company Admin', 'Full access within company'),
  ('STATION_OPERATOR', 'Station Operator', 'Station operations and monitoring'),
  ('VENDOR', 'Vendor', 'Vendor-scoped access'),
  ('AMO', 'AMO', 'Operations team access'),
  ('STAFF', 'Staff', 'Self-service staff access')
) as x(code, name, description)
where c.code = 'DEMO'
on conflict do nothing;

-- -----------------------------------------------------------------------------
-- Role → Permission mapping
-- -----------------------------------------------------------------------------

-- Platform super admin gets all permissions
insert into AMS_role_permission_map (id, AMS_role_id, AMS_permission_id)
select
  gen_random_uuid(),
  r.id,
  p.id
from AMS_role r
join AMS_permission p on true
where r.code = 'PLATFORM_SUPER_ADMIN'
on conflict (AMS_role_id, AMS_permission_id) do nothing;

-- Company admin (DEMO) gets all company_* permissions (and can read company settings)
insert into AMS_role_permission_map (id, AMS_role_id, AMS_permission_id)
select
  gen_random_uuid(),
  r.id,
  p.id
from AMS_role r
join AMS_permission p on (
  p.code like 'COMPANY_%'
)
where r.code = 'COMPANY_ADMIN'
on conflict (AMS_role_id, AMS_permission_id) do nothing;

-- Station operator (DEMO)
insert into AMS_role_permission_map (id, AMS_role_id, AMS_permission_id)
select gen_random_uuid(), r.id, p.id
from AMS_role r
join AMS_permission p on p.code in (
  'COMPANY_ORG_READ',
  'COMPANY_STAFF_READ',
  'COMPANY_ATTENDANCE_READ',
  'COMPANY_ATTENDANCE_PUNCH',
  'COMPANY_DEVICE_READ',
  'COMPANY_REPORT_READ'
)
where r.code = 'STATION_OPERATOR'
on conflict (AMS_role_id, AMS_permission_id) do nothing;

-- Vendor (DEMO)
insert into AMS_role_permission_map (id, AMS_role_id, AMS_permission_id)
select gen_random_uuid(), r.id, p.id
from AMS_role r
join AMS_permission p on p.code in (
  'COMPANY_REPORT_READ'
)
where r.code = 'VENDOR'
on conflict (AMS_role_id, AMS_permission_id) do nothing;

-- AMO (DEMO)
insert into AMS_role_permission_map (id, AMS_role_id, AMS_permission_id)
select gen_random_uuid(), r.id, p.id
from AMS_role r
join AMS_permission p on p.code in (
  'COMPANY_ORG_READ',
  'COMPANY_STAFF_READ',
  'COMPANY_ATTENDANCE_READ',
  'COMPANY_ATTENDANCE_PUNCH',
  'COMPANY_SHIFT_READ',
  'COMPANY_DEVICE_READ',
  'COMPANY_SUPPORT_READ',
  'COMPANY_REPORT_READ'
)
where r.code = 'AMO'
on conflict (AMS_role_id, AMS_permission_id) do nothing;

-- Staff (DEMO)
insert into AMS_role_permission_map (id, AMS_role_id, AMS_permission_id)
select gen_random_uuid(), r.id, p.id
from AMS_role r
join AMS_permission p on p.code in (
  'COMPANY_ATTENDANCE_READ',
  'COMPANY_ATTENDANCE_PUNCH',
  'COMPANY_REPORT_READ',
  'STAFF_SUPPORT_TICKET'
)
where r.code = 'STAFF'
on conflict (AMS_role_id, AMS_permission_id) do nothing;

-- -----------------------------------------------------------------------------
-- Assign demo admin user roles
-- -----------------------------------------------------------------------------

-- Platform Super Admin (global)
insert into AMS_user_role_map (id, AMS_user_id, AMS_role_id, AMS_company_id, is_active)
select
  gen_random_uuid(),
  u.id,
  r.id,
  null,
  true
from AMS_user u
join AMS_role r on r.code = 'PLATFORM_SUPER_ADMIN'
where lower(u.email) = lower('admin@demo.local')
on conflict (AMS_user_id, AMS_role_id, AMS_company_id) do nothing;

-- Company Admin for DEMO
insert into AMS_user_role_map (id, AMS_user_id, AMS_role_id, AMS_company_id, is_active)
select
  gen_random_uuid(),
  u.id,
  r.id,
  c.id,
  true
from AMS_user u
join AMS_company c on c.code = 'DEMO'
join AMS_role r on r.code = 'COMPANY_ADMIN' and r.AMS_company_id = c.id
where lower(u.email) = lower('admin@demo.local')
on conflict (AMS_user_id, AMS_role_id, AMS_company_id) do nothing;

commit;

