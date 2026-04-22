-- Phase 7 foundation: attendance rollups + reporting RPC
begin;

-- -----------------------------------------------------------------------------
-- Daily rollup table (company + staff + shift_date)
-- -----------------------------------------------------------------------------

create table if not exists AMS_attendance_daily_rollup (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  shift_date date not null,
  -- Convenience meta
  last_station_id uuid null,
  first_punch_at timestamptz null,
  last_punch_at timestamptz null,
  first_in_at timestamptz null,
  last_out_at timestamptz null,
  total_punches int not null default 0,
  in_punches int not null default 0,
  out_punches int not null default 0,
  break_in_punches int not null default 0,
  break_out_punches int not null default 0,
  within_geofence_true int not null default 0,
  within_geofence_false int not null default 0,
  within_geofence_unknown int not null default 0,
  face_score_avg numeric(10,4) null,
  status text not null default 'computed',
  meta_json jsonb not null default '{}'::jsonb,
  computed_at timestamptz not null default AMS_fn_now_utc(),
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_attendance_daily_rollup_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_attendance_daily_rollup_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade,
  constraint AMS_attendance_daily_rollup_status_ck
    check (status in ('computed','stale','error'))
);

create unique index if not exists AMS_attendance_daily_rollup_company_staff_date_uk
  on AMS_attendance_daily_rollup (AMS_company_id, AMS_staff_id, shift_date);

create index if not exists AMS_attendance_daily_rollup_company_date_idx
  on AMS_attendance_daily_rollup (AMS_company_id, shift_date desc);

create trigger AMS_attendance_daily_rollup_set_updated_at_trg
before update on AMS_attendance_daily_rollup
for each row execute function AMS_fn_set_updated_at();

alter table AMS_attendance_daily_rollup enable row level security;

-- -----------------------------------------------------------------------------
-- Rollup recompute function (server-side engine primitive)
-- -----------------------------------------------------------------------------

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
  v_rows int := 0;
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

  -- Remove existing rollups for range then rebuild from logs.
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

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

grant execute on function AMS_fn_attendance_daily_rollup_refresh(uuid, date, date) to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Reporting RPC (PostgREST friendly)
-- -----------------------------------------------------------------------------

create or replace function AMS_sp_company_attendance_daily_report(
  p_access_token text,
  p_from date,
  p_to date,
  p_staff_id uuid default null
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

  -- Ensure rollups exist for requested range (idempotent refresh).
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
          d.first_punch_at,
          d.last_punch_at,
          d.first_in_at,
          d.last_out_at,
          d.total_punches,
          d.in_punches,
          d.out_punches,
          d.break_in_punches,
          d.break_out_punches,
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
        order by d.shift_date desc
      ) r
    )
  );
end;
$$;

grant execute on function AMS_sp_company_attendance_daily_report(text, date, date, uuid) to anon, authenticated, service_role;
notify pgrst, 'reload schema';

commit;

