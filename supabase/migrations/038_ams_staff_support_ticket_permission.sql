-- Staff mobile: create support tickets and list own tickets (STAFF_SUPPORT_TICKET).
-- Admins keep COMPANY_SUPPORT_READ / COMPANY_SUPPORT_WRITE for full company queue.

begin;

insert into AMS_permission (id, code, name, description, is_active)
values (
  gen_random_uuid(),
  'STAFF_SUPPORT_TICKET',
  'Staff: Support tickets (own)',
  'Create support tickets and view tickets you opened',
  true
)
on conflict (code) do update
set
  name = excluded.name,
  description = excluded.description,
  is_active = excluded.is_active;

insert into AMS_role_permission_map (id, AMS_role_id, AMS_permission_id)
select gen_random_uuid(), r.id, p.id
from AMS_permission p
join AMS_role r on r.is_platform_role = false and r.code = 'STAFF'
where p.code = 'STAFF_SUPPORT_TICKET'
on conflict (AMS_role_id, AMS_permission_id) do nothing;

commit;
