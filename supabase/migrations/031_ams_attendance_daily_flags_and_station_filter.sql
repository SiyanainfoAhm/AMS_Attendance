-- Phase 7: automation flags (missing OUT / missing BREAK_OUT) + station filter in report
begin;

alter table AMS_attendance_daily_rollup
  add column if not exists has_open_session boolean not null default false,
  add column if not exists has_open_break boolean not null default false,
  add column if not exists missing_out boolean not null default false,
  add column if not exists missing_break_out boolean not null default false;

drop function if exists AMS_fn_attendance_day_totals(uuid, uuid, date);

create or replace function AMS_fn_attendance_day_totals(
  p_company_id uuid,
  p_staff_id uuid,
  p_shift_date date
)
returns table(
  total_work_minutes int,
  total_break_minutes int,
  total_active_minutes int,
  last_punch_type text,
  has_open_session boolean,
  has_open_break boolean,
  missing_out boolean,
  missing_break_out boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_in_at timestamptz := null;
  v_break_at timestamptz := null;
  v_work_seconds bigint := 0;
  v_break_seconds bigint := 0;
  v_last_type text := null;
  v_open_session boolean := false;
  v_open_break boolean := false;
begin
  if p_company_id is null or p_staff_id is null or p_shift_date is null then
    raise exception 'invalid_args';
  end if;

  for r in
    select punch_type, punch_at
    from AMS_attendance_log
    where AMS_company_id = p_company_id
      and AMS_staff_id = p_staff_id
      and coalesce(shift_date, (punch_at at time zone 'UTC')::date) = p_shift_date
    order by punch_at asc
  loop
    v_last_type := r.punch_type;

    if r.punch_type = 'in' then
      if v_in_at is null then
        v_in_at := r.punch_at;
      end if;
      v_break_at := null;

    elsif r.punch_type = 'break_in' then
      if v_in_at is not null and v_break_at is null then
        v_break_at := r.punch_at;
      end if;

    elsif r.punch_type = 'break_out' then
      if v_in_at is not null and v_break_at is not null then
        v_break_seconds := v_break_seconds + extract(epoch from (r.punch_at - v_break_at))::bigint;
        v_break_at := null;
      end if;

    elsif r.punch_type = 'out' then
      if v_in_at is not null then
        if v_break_at is not null then
          v_break_seconds := v_break_seconds + extract(epoch from (r.punch_at - v_break_at))::bigint;
          v_break_at := null;
        end if;
        v_work_seconds := v_work_seconds + extract(epoch from (r.punch_at - v_in_at))::bigint;
        v_in_at := null;
      end if;
    end if;
  end loop;

  v_open_session := (v_in_at is not null);
  v_open_break := (v_break_at is not null);

  total_work_minutes := floor(v_work_seconds / 60.0)::int;
  total_break_minutes := floor(v_break_seconds / 60.0)::int;
  total_active_minutes := greatest(0, total_work_minutes - total_break_minutes);
  last_punch_type := v_last_type;

  has_open_session := v_open_session;
  has_open_break := v_open_break;
  missing_out := v_open_session;
  missing_break_out := v_open_break;

  return next;
end;
$$;

grant execute on function AMS_fn_attendance_day_totals(uuid, uuid, date) to anon, authenticated, service_role;

-- Update refresh function to also fill the automation flags.
create or replace function AMS_fn_attendance_daily_rollup_refresh(
  p_company_id uuid,
  p_from date,
  p_to date
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v recORD;
  v_tot record;
  v_dummy int := 0;
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

  delete from AMS_attendance_daily_rollup r
   where r.AMS_company_id = p_company_id
     and r.shift_date between p_from and p_to;

  with base as (
    select
      l.AMS_company_id,
      l.AMS_staff_id,
      coalesce(l.shift_date, (l.punch_at at time zone 'UTC')::date) as shift_date,
      l.AMS_station_id,
      l.punch_type,
      l.punch_at,
      l.within_geofence,
      l.face_match_score
    from AMS_attendance_log l
    where l.AMS_company_id = p_company_id
      and coalesce(l.shift_date, (l.punch_at at time zone 'UTC')::date) between p_from and p_to
  ),
  last_station as (
    select distinct on (AMS_company_id, AMS_staff_id, shift_date)
      AMS_company_id, AMS_staff_id, shift_date, AMS_station_id as last_station_id
    from base
    order by AMS_company_id, AMS_staff_id, shift_date, punch_at desc
  ),
  agg as (
    select
      b.AMS_company_id,
      b.AMS_staff_id,
      b.shift_date,
      min(b.punch_at) as first_punch_at,
      max(b.punch_at) as last_punch_at,
      min(b.punch_at) filter (where b.punch_type = 'in') as first_in_at,
      max(b.punch_at) filter (where b.punch_type = 'out') as last_out_at,
      count(*)::int as total_punches,
      count(*) filter (where b.punch_type = 'in')::int as in_punches,
      count(*) filter (where b.punch_type = 'out')::int as out_punches,
      count(*) filter (where b.punch_type = 'break_in')::int as break_in_punches,
      count(*) filter (where b.punch_type = 'break_out')::int as break_out_punches,
      count(*) filter (where b.within_geofence is true)::int as within_geofence_true,
      count(*) filter (where b.within_geofence is false)::int as within_geofence_false,
      count(*) filter (where b.within_geofence is null)::int as within_geofence_unknown,
      avg(b.face_match_score) as face_score_avg
    from base b
    group by b.AMS_company_id, b.AMS_staff_id, b.shift_date
  )
  insert into AMS_attendance_daily_rollup (
    id,
    AMS_company_id,
    AMS_staff_id,
    shift_date,
    last_station_id,
    first_punch_at,
    last_punch_at,
    first_in_at,
    last_out_at,
    total_punches,
    in_punches,
    out_punches,
    break_in_punches,
    break_out_punches,
    total_work_minutes,
    total_break_minutes,
    total_active_minutes,
    last_punch_type,
    has_open_session,
    has_open_break,
    missing_out,
    missing_break_out,
    within_geofence_true,
    within_geofence_false,
    within_geofence_unknown,
    face_score_avg,
    status,
    meta_json,
    computed_at,
    created_at,
    updated_at,
    created_by,
    updated_by
  )
  select
    gen_random_uuid(),
    a.AMS_company_id,
    a.AMS_staff_id,
    a.shift_date,
    ls.last_station_id,
    a.first_punch_at,
    a.last_punch_at,
    a.first_in_at,
    a.last_out_at,
    a.total_punches,
    a.in_punches,
    a.out_punches,
    a.break_in_punches,
    a.break_out_punches,
    0,0,0,null,false,false,false,false,
    a.within_geofence_true,
    a.within_geofence_false,
    a.within_geofence_unknown,
    a.face_score_avg,
    'computed',
    '{}'::jsonb,
    AMS_fn_now_utc(),
    AMS_fn_now_utc(),
    AMS_fn_now_utc(),
    null,
    null
  from agg a
  left join last_station ls
    on ls.AMS_company_id = a.AMS_company_id
   and ls.AMS_staff_id = a.AMS_staff_id
   and ls.shift_date = a.shift_date;

  for v in
    select AMS_staff_id, shift_date
    from AMS_attendance_daily_rollup
    where AMS_company_id = p_company_id
      and shift_date between p_from and p_to
  loop
    select * into v_tot
    from AMS_fn_attendance_day_totals(p_company_id, v.AMS_staff_id, v.shift_date)
    limit 1;

    update AMS_attendance_daily_rollup d
       set total_work_minutes = coalesce(v_tot.total_work_minutes, 0),
           total_break_minutes = coalesce(v_tot.total_break_minutes, 0),
           total_active_minutes = coalesce(v_tot.total_active_minutes, 0),
           last_punch_type = v_tot.last_punch_type,
           has_open_session = coalesce(v_tot.has_open_session, false),
           has_open_break = coalesce(v_tot.has_open_break, false),
           missing_out = coalesce(v_tot.missing_out, false),
           missing_break_out = coalesce(v_tot.missing_break_out, false)
     where d.AMS_company_id = p_company_id
       and d.AMS_staff_id = v.AMS_staff_id
       and d.shift_date = v.shift_date;
  end loop;

  return v_dummy;
end;
$$;

grant execute on function AMS_fn_attendance_daily_rollup_refresh(uuid, date, date) to anon, authenticated, service_role;

-- Update report signature to accept optional station filter, and include flags in items.
drop function if exists AMS_sp_company_attendance_daily_report(text, date, date, uuid);

create or replace function AMS_sp_company_attendance_daily_report(
  p_access_token text,
  p_from date,
  p_to date,
  p_staff_id uuid default null,
  p_station_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_rows int;
begin
  select * into v_ctx from AMS_fn_require_company_context(p_access_token) limit 1;

  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ATTENDANCE_READ') then
    raise exception 'forbidden';
  end if;

  if p_from is null or p_to is null then
    raise exception 'date_range_required';
  end if;
  if p_from > p_to then
    raise exception 'invalid_date_range';
  end if;

  v_rows := AMS_fn_attendance_daily_rollup_refresh(v_ctx.company_id, p_from, p_to);

  return jsonb_build_object(
    'ok', true,
    'refreshed', v_rows,
    'items', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.shift_date desc), '[]'::jsonb)
      from (
        select
          d.shift_date,
          d.AMS_staff_id as staff_id,
          s.staff_code,
          s.full_name,
          d.last_station_id as station_id,
          st.code as station_code,
          st.name as station_name,
          d.last_punch_type,
          d.first_punch_at,
          d.last_punch_at,
          d.first_in_at,
          d.last_out_at,
          d.total_punches,
          d.in_punches,
          d.out_punches,
          d.break_in_punches,
          d.break_out_punches,
          d.total_work_minutes,
          d.total_break_minutes,
          d.total_active_minutes,
          d.has_open_session,
          d.has_open_break,
          d.missing_out,
          d.missing_break_out,
          d.within_geofence_true,
          d.within_geofence_false,
          d.within_geofence_unknown,
          d.face_score_avg,
          d.status,
          d.computed_at
        from AMS_attendance_daily_rollup d
        join AMS_staff s on s.id = d.AMS_staff_id
        left join AMS_station st on st.id = d.last_station_id
        where d.AMS_company_id = v_ctx.company_id
          and d.shift_date between p_from and p_to
          and (p_staff_id is null or d.AMS_staff_id = p_staff_id)
          and (p_station_id is null or d.last_station_id = p_station_id)
        order by d.shift_date desc
      ) r
    )
  );
end;
$$;

grant execute on function AMS_sp_company_attendance_daily_report(text, date, date, uuid, uuid) to anon, authenticated, service_role;
notify pgrst, 'reload schema';

commit;

