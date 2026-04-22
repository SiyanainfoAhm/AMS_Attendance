-- Audit case generator that RETURNS inserted cases (for notifications/cron).
-- This complements AMS_fn_audit_generate_missing_attendance_from_rollup which only returns a count.

begin;

create or replace function AMS_fn_audit_generate_missing_attendance_from_rollup_returning(
  p_company_id uuid,
  p_from date,
  p_to date,
  p_staff_id uuid default null
)
returns table (
  audit_case_id uuid,
  staff_id uuid,
  shift_day date,
  case_kind text,
  title text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_company_id is null then
    raise exception 'company_id_required';
  end if;
  if p_from is null or p_to is null then
    raise exception 'date_range_required';
  end if;
  if p_from > p_to then
    raise exception 'invalid_date_range';
  end if;

  return query
  with src as (
    select
      r.AMS_company_id,
      r.AMS_staff_id,
      r.shift_date,
      'missing_out'::text as case_type,
      'Missing OUT punch'::text as title,
      'You have an open session for this day. Please confirm what happened and provide details.'::text as description,
      jsonb_build_object(
        'shift_date', r.shift_date,
        'last_punch_type', r.last_punch_type,
        'first_in_at', r.first_in_at,
        'last_punch_at', r.last_punch_at,
        'total_punches', r.total_punches
      ) as payload_json
    from AMS_attendance_daily_rollup r
    where r.AMS_company_id = p_company_id
      and r.shift_date between p_from and p_to
      and r.missing_out is true
      and (p_staff_id is null or r.AMS_staff_id = p_staff_id)
  ),
  ins as (
    insert into AMS_audit_case (
      AMS_company_id, AMS_staff_id, case_type, status, shift_date, title, description, payload_json,
      created_at, updated_at, created_by, updated_by
    )
    select
      s.AMS_company_id, s.AMS_staff_id, s.case_type, 'open', s.shift_date, s.title, s.description, s.payload_json,
      AMS_fn_now_utc(), AMS_fn_now_utc(), null, null
    from src s
    on conflict (AMS_company_id, AMS_staff_id, shift_date, case_type) do nothing
    returning
      AMS_audit_case.id,
      AMS_audit_case.AMS_staff_id as staff_id,
      AMS_audit_case.shift_date as shift_day,
      AMS_audit_case.case_type as case_kind,
      AMS_audit_case.title
  ),
  src2 as (
    select
      r.AMS_company_id,
      r.AMS_staff_id,
      r.shift_date,
      'missing_break_out'::text as case_type,
      'Missing Break OUT punch'::text as title,
      'You have an open break for this day. Please confirm what happened and provide details.'::text as description,
      jsonb_build_object(
        'shift_date', r.shift_date,
        'last_punch_type', r.last_punch_type,
        'first_in_at', r.first_in_at,
        'last_punch_at', r.last_punch_at,
        'total_punches', r.total_punches
      ) as payload_json
    from AMS_attendance_daily_rollup r
    where r.AMS_company_id = p_company_id
      and r.shift_date between p_from and p_to
      and r.missing_break_out is true
      and (p_staff_id is null or r.AMS_staff_id = p_staff_id)
  ),
  ins2 as (
    insert into AMS_audit_case (
      AMS_company_id, AMS_staff_id, case_type, status, shift_date, title, description, payload_json,
      created_at, updated_at, created_by, updated_by
    )
    select
      s.AMS_company_id, s.AMS_staff_id, s.case_type, 'open', s.shift_date, s.title, s.description, s.payload_json,
      AMS_fn_now_utc(), AMS_fn_now_utc(), null, null
    from src2 s
    on conflict (AMS_company_id, AMS_staff_id, shift_date, case_type) do nothing
    returning
      AMS_audit_case.id,
      AMS_audit_case.AMS_staff_id as staff_id,
      AMS_audit_case.shift_date as shift_day,
      AMS_audit_case.case_type as case_kind,
      AMS_audit_case.title
  )
  select ins.id as audit_case_id, ins.staff_id, ins.shift_day, ins.case_kind, ins.title
  from ins
  union all
  select ins2.id as audit_case_id, ins2.staff_id, ins2.shift_day, ins2.case_kind, ins2.title
  from ins2;
end;
$$;

grant execute on function AMS_fn_audit_generate_missing_attendance_from_rollup_returning(uuid, date, date, uuid)
  to anon, authenticated, service_role;

commit;

