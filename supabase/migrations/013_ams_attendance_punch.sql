-- Attendance punch (write path) + permission COMPANY_ATTENDANCE_PUNCH

begin;

insert into AMS_permission (id, code, name, description, is_active)
values (
  gen_random_uuid(),
  'COMPANY_ATTENDANCE_PUNCH',
  'Company: Attendance punch',
  'Record in/out/break punches for staff (kiosk/mobile/admin)',
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
join AMS_role r
  on r.is_platform_role = false
  and r.code in ('COMPANY_ADMIN', 'STATION_OPERATOR', 'STAFF', 'AMO')
where p.code = 'COMPANY_ATTENDANCE_PUNCH'
on conflict (AMS_role_id, AMS_permission_id) do nothing;

create or replace function AMS_sp_company_attendance_punch(
  p_access_token text,
  p_staff_id uuid,
  p_punch_type text,
  p_station_id uuid default null,
  p_punch_at timestamptz default null,
  p_within_geofence boolean default null,
  p_face_match_score numeric default null,
  p_device_id uuid default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_ctx record;
  v_now timestamptz := AMS_fn_now_utc();
  v_punch_at timestamptz := coalesce(p_punch_at, v_now);
  v_shift_date date := (v_punch_at at time zone 'UTC')::date;
  v_id uuid := gen_random_uuid();
begin
  select * into v_ctx from AMS_fn_require_company_context(p_access_token) limit 1;

  if not (
    AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ATTENDANCE_WRITE')
    or AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ATTENDANCE_PUNCH')
  ) then
    raise exception 'forbidden';
  end if;

  if p_staff_id is null then
    raise exception 'staff_id_required';
  end if;

  if p_punch_type is null or p_punch_type not in ('in', 'out', 'break_in', 'break_out') then
    raise exception 'invalid_punch_type';
  end if;

  if not exists (
    select 1
    from AMS_staff s
    where s.id = p_staff_id
      and s.AMS_company_id = v_ctx.company_id
      and s.status = 'active'
      and s.is_active = true
  ) then
    raise exception 'staff_not_found';
  end if;

  if p_station_id is not null then
    if not exists (
      select 1
      from AMS_station st
      where st.id = p_station_id
        and st.AMS_company_id = v_ctx.company_id
    ) then
      raise exception 'station_not_found';
    end if;
  end if;

  if p_device_id is not null then
    if not exists (
      select 1
      from AMS_device d
      where d.id = p_device_id
        and d.AMS_company_id = v_ctx.company_id
    ) then
      raise exception 'device_not_found';
    end if;
  end if;

  insert into AMS_attendance_log (
    id,
    AMS_company_id,
    AMS_staff_id,
    AMS_station_id,
    AMS_device_id,
    punch_type,
    punch_at,
    within_geofence,
    face_match_score,
    shift_date,
    meta_json,
    created_at,
    updated_at,
    created_by,
    updated_by
  )
  values (
    v_id,
    v_ctx.company_id,
    p_staff_id,
    p_station_id,
    p_device_id,
    p_punch_type,
    v_punch_at,
    p_within_geofence,
    p_face_match_score,
    v_shift_date,
    '{}'::jsonb,
    v_now,
    v_now,
    v_ctx.user_id,
    v_ctx.user_id
  );

  insert into AMS_audit_log (
    id,
    AMS_company_id,
    actor_user_id,
    action_code,
    entity_type,
    entity_id,
    details_json,
    occurred_at,
    created_at,
    updated_at,
    created_by,
    updated_by
  )
  values (
    gen_random_uuid(),
    v_ctx.company_id,
    v_ctx.user_id,
    'COMPANY_ATTENDANCE_PUNCH',
    'AMS_attendance_log',
    v_id,
    jsonb_build_object(
      'staff_id', p_staff_id,
      'station_id', p_station_id,
      'punch_type', p_punch_type,
      'punch_at', v_punch_at
    ),
    v_now,
    v_now,
    v_now,
    v_ctx.user_id,
    v_ctx.user_id
  );

  return jsonb_build_object(
    'id', v_id,
    'punch_at', v_punch_at,
    'shift_date', v_shift_date
  );
end;
$$;

commit;
