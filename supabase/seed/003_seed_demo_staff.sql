-- Seed demo staff + minimal org objects for DEMO company
-- Safe to re-run (uses UPSERTs).

begin;

-- -----------------------------------------------------------------------------
-- Resolve demo company
-- -----------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from AMS_company where code = 'DEMO') then
    raise exception 'DEMO company not found. Run seed/001_seed_platform.sql first.';
  end if;
end;
$$;

with c as (
  select id as company_id from AMS_company where code = 'DEMO' limit 1
),
z as (
  insert into AMS_zone (id, AMS_company_id, code, name, description, is_active)
  select gen_random_uuid(), c.company_id, 'DEMO-Z01', 'Demo Zone', 'Seed zone for demo data', true
  from c
  on conflict (AMS_company_id, code) do update
    set name = excluded.name,
        description = excluded.description,
        is_active = excluded.is_active,
        updated_at = AMS_fn_now_utc()
  returning id as zone_id
),
z2 as (
  select zone_id from z
  union all
  select id from AMS_zone where AMS_company_id = (select company_id from c) and code = 'DEMO-Z01' limit 1
),
b as (
  insert into AMS_branch (id, AMS_company_id, AMS_zone_id, code, name, address_json, latitude, longitude, is_active)
  select gen_random_uuid(), c.company_id, (select zone_id from z2), 'DEMO-B01', 'Demo Branch',
         jsonb_build_object('line1','Demo Road','city','Ahmedabad','state','GJ','country','IN'),
         23.0225, 72.5714, true
  from c
  on conflict (AMS_company_id, code) do update
    set name = excluded.name,
        AMS_zone_id = excluded.AMS_zone_id,
        address_json = excluded.address_json,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        is_active = excluded.is_active,
        updated_at = AMS_fn_now_utc()
  returning id as branch_id
),
b2 as (
  select branch_id from b
  union all
  select id from AMS_branch where AMS_company_id = (select company_id from c) and code = 'DEMO-B01' limit 1
),
s as (
  insert into AMS_station (id, AMS_company_id, AMS_zone_id, AMS_branch_id, code, name, address_json, latitude, longitude, is_active)
  select gen_random_uuid(), c.company_id, (select zone_id from z2), (select branch_id from b2),
         'DEMO-ST01', 'Demo Station',
         jsonb_build_object('line1','Demo Station','city','Ahmedabad','state','GJ','country','IN'),
         23.0225, 72.5714, true
  from c
  on conflict (AMS_company_id, code) do update
    set name = excluded.name,
        AMS_zone_id = excluded.AMS_zone_id,
        AMS_branch_id = excluded.AMS_branch_id,
        address_json = excluded.address_json,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        is_active = excluded.is_active,
        updated_at = AMS_fn_now_utc()
  returning id as station_id
),
s2 as (
  select station_id from s
  union all
  select id from AMS_station where AMS_company_id = (select company_id from c) and code = 'DEMO-ST01' limit 1
),
gf as (
  insert into AMS_geofence (
    id,
    AMS_company_id,
    AMS_station_id,
    code,
    name,
    geofence_type,
    center_lat,
    center_lng,
    radius_m,
    is_active
  )
  select
    gen_random_uuid(),
    c.company_id,
    (select station_id from s2),
    'DEMO-GF01',
    'Demo Station Geofence',
    'circle',
    23.0225,
    72.5714,
    250,
    true
  from c
  on conflict (AMS_company_id, code) do update
    set AMS_station_id = excluded.AMS_station_id,
        name = excluded.name,
        geofence_type = excluded.geofence_type,
        center_lat = excluded.center_lat,
        center_lng = excluded.center_lng,
        radius_m = excluded.radius_m,
        is_active = excluded.is_active,
        updated_at = AMS_fn_now_utc()
  returning id as geofence_id
),
staff_seed as (
  select * from (values
    ('S0001','Aarav Patel','9000000001','staff1@demo.local','male','full_time'),
    ('S0002','Diya Sharma','9000000002','staff2@demo.local','female','full_time'),
    ('S0003','Kabir Verma','9000000003','staff3@demo.local','male','contract'),
    ('S0004','Ananya Iyer','9000000004','staff4@demo.local','female','contract'),
    ('S0005','Vivaan Singh','9000000005','staff5@demo.local','male','full_time'),
    ('S0006','Ishita Gupta','9000000006','staff6@demo.local','female','part_time'),
    ('S0007','Arjun Mehta','9000000007','staff7@demo.local','male','part_time'),
    ('S0008','Meera Nair','9000000008','staff8@demo.local','female','full_time')
  ) as t(staff_code, full_name, mobile, email, gender, employment_type)
),
upsert_staff as (
  insert into AMS_staff (
    id,
    AMS_company_id,
    staff_code,
    full_name,
    mobile,
    email,
    gender,
    join_date,
    employment_type,
    status,
    is_active,
    meta_json
  )
  select
    gen_random_uuid(),
    c.company_id,
    upper(t.staff_code),
    t.full_name,
    t.mobile,
    lower(t.email),
    t.gender,
    current_date - interval '30 days',
    t.employment_type,
    'active',
    true,
    jsonb_build_object('seed', true)
  from staff_seed t
  cross join c
  on conflict (AMS_company_id, staff_code) do update
    set full_name = excluded.full_name,
        mobile = excluded.mobile,
        email = excluded.email,
        gender = excluded.gender,
        employment_type = excluded.employment_type,
        status = excluded.status,
        is_active = excluded.is_active,
        meta_json = coalesce(AMS_staff.meta_json, '{}'::jsonb) || excluded.meta_json,
        updated_at = AMS_fn_now_utc()
  returning id as staff_id
),
all_staff as (
  select id as staff_id
  from AMS_staff
  where AMS_company_id = (select company_id from c)
    and staff_code in (select upper(staff_code) from staff_seed)
)
insert into AMS_staff_station_map (
  id,
  AMS_company_id,
  AMS_staff_id,
  AMS_station_id,
  is_primary,
  is_active
)
select
  gen_random_uuid(),
  (select company_id from c),
  st.staff_id,
  (select station_id from s2),
  true,
  true
from all_staff st
on conflict (AMS_staff_id, AMS_station_id) do update
  set is_primary = excluded.is_primary,
      is_active = excluded.is_active,
      updated_at = AMS_fn_now_utc();

-- -----------------------------------------------------------------------------
-- Create a demo STAFF login user (staff1@demo.local) and map it to S0001
-- Password: ChangeMe@123
-- Requires migrations 001, 002, 003, 006, 008, 010, 014.
-- -----------------------------------------------------------------------------

with c as (
  select id as company_id from AMS_company where code = 'DEMO' limit 1
),
u as (
  insert into AMS_user (id, display_name, email, password_hash, password_algo, is_active, is_platform_super_admin)
  values (gen_random_uuid(), 'Demo Staff 1', 'staff1@demo.local', AMS_fn_password_hash_bcrypt('ChangeMe@123'), 'bcrypt', true, false)
  on conflict do nothing
  returning id as user_id
),
u2 as (
  select user_id from u
  union all
  select id from AMS_user where lower(email) = lower('staff1@demo.local') limit 1
),
staff1 as (
  select id as staff_id
  from AMS_staff
  where AMS_company_id = (select company_id from c)
    and staff_code = 'S0001'
  limit 1
),
map_company as (
  insert into AMS_user_company_map (id, AMS_user_id, AMS_company_id, is_active)
  select gen_random_uuid(), (select user_id from u2), (select company_id from c), true
  on conflict (AMS_user_id, AMS_company_id) do update
    set is_active = excluded.is_active,
        updated_at = AMS_fn_now_utc()
  returning 1
),
role_staff as (
  select r.id as role_id
  from AMS_role r
  join AMS_company c2 on c2.id = r.AMS_company_id
  where c2.code = 'DEMO' and r.code = 'STAFF'
  limit 1
),
assign_role as (
  insert into AMS_user_role_map (id, AMS_user_id, AMS_role_id, AMS_company_id, is_active)
  select gen_random_uuid(), (select user_id from u2), (select role_id from role_staff), (select company_id from c), true
  on conflict (AMS_user_id, AMS_role_id, AMS_company_id) do update
    set is_active = excluded.is_active,
        updated_at = AMS_fn_now_utc()
  returning 1
)
insert into AMS_user_staff_map (id, AMS_company_id, AMS_user_id, AMS_staff_id, is_active, created_at, updated_at)
select gen_random_uuid(), (select company_id from c), (select user_id from u2), (select staff_id from staff1), true, AMS_fn_now_utc(), AMS_fn_now_utc()
on conflict (AMS_company_id, AMS_user_id) do update
  set AMS_staff_id = excluded.AMS_staff_id,
      is_active = excluded.is_active,
      updated_at = AMS_fn_now_utc();

commit;

