-- Attendance: same-company-day IN/OUT semantics + open-segment duration rules for totals/flags
begin;

-- -----------------------------------------------------------------------------
-- Day totals: company-local calendar day + open IN/break uses least(now, end_of_local_day)
-- Active = work_span - break_span (break spans use same effective end rule)
-- -----------------------------------------------------------------------------

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
  v_tz text;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_eff_end timestamptz;
  v_now timestamptz := AMS_fn_now_utc();

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

  select coalesce(nullif(trim(s.timezone), ''), 'UTC')
    into v_tz
  from AMS_company c
  left join AMS_company_settings s on s.AMS_company_id = c.id
  where c.id = p_company_id;

  v_day_start := (p_shift_date::timestamp at time zone v_tz);
  v_day_end := (((p_shift_date + 1)::timestamp) at time zone v_tz);
  v_eff_end := least(v_now, v_day_end);

  for r in
    select punch_type, punch_at
    from AMS_attendance_log
    where AMS_company_id = p_company_id
      and AMS_staff_id = p_staff_id
      and punch_at >= v_day_start
      and punch_at < v_day_end
    order by punch_at asc
  loop
    v_last_type := r.punch_type;

    if r.punch_type = 'in' then
      -- If a new IN arrives while a session is still open, treat the prior session as
      -- implicitly closed at end-of-company-day (missing OUT path / audit), then start fresh.
      if v_in_at is not null then
        if v_break_at is not null then
          v_break_seconds := v_break_seconds + greatest(0, extract(epoch from (least(r.punch_at, v_day_end) - v_break_at))::bigint);
          v_break_at := null;
        end if;
        v_work_seconds := v_work_seconds + greatest(0, extract(epoch from (least(r.punch_at, v_day_end) - v_in_at))::bigint);
        v_in_at := null;
      end if;

      v_in_at := r.punch_at;
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

  -- Open break segment: close to effective end-of-day (or now if earlier)
  if v_in_at is not null and v_break_at is not null then
    v_break_seconds := v_break_seconds + greatest(0, extract(epoch from (v_eff_end - v_break_at))::bigint);
    v_break_at := null;
  end if;

  -- Open work session: close to effective end-of-day (or now if earlier)
  if v_in_at is not null then
    v_work_seconds := v_work_seconds + greatest(0, extract(epoch from (v_eff_end - v_in_at))::bigint);
    -- Keep session "open" for audit purposes even though we attributed time to end-of-day cap.
    v_break_at := null;
  end if;

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

-- Backfill shift_date to company-local calendar day (older rows used UTC date in the punch RPC).
-- Timezone is stored on AMS_company_settings, not AMS_company.
update AMS_attendance_log l
   set shift_date = (l.punch_at at time zone coalesce(nullif(trim(s.timezone), ''), 'UTC'))::date
  from AMS_company c
  left join AMS_company_settings s on s.AMS_company_id = c.id
 where c.id = l.AMS_company_id
   and l.shift_date is distinct from (l.punch_at at time zone coalesce(nullif(trim(s.timezone), ''), 'UTC'))::date;

-- -----------------------------------------------------------------------------
-- Punch: store shift_date in company-local calendar day + enforce same-day OUT
-- -----------------------------------------------------------------------------

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
  v_tz text;
  v_shift_date date := (v_punch_at at time zone 'UTC')::date;
  v_id uuid := gen_random_uuid();
  v_mapped_staff uuid;
  v_staff_login_scope boolean;
  v_last_in timestamptz;
  v_last_in_day date;
  v_punch_day date;
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

  select coalesce(nullif(trim(s.timezone), ''), 'UTC')
    into v_tz
  from AMS_company c
  left join AMS_company_settings s on s.AMS_company_id = c.id
  where c.id = v_ctx.company_id;

  v_shift_date := (v_punch_at at time zone v_tz)::date;
  v_punch_day := v_shift_date;

  -- Users with STAFF role and punch (but not attendance write) may only punch their mapped staff row
  v_staff_login_scope :=
    AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ATTENDANCE_PUNCH')
    and not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ATTENDANCE_WRITE')
    and not AMS_fn_is_platform_super_admin(v_ctx.user_id)
    and exists (
      select 1
      from AMS_user_role_map urm
      join AMS_role r on r.id = urm.AMS_role_id
      where urm.AMS_user_id = v_ctx.user_id
        and urm.is_active = true
        and r.is_active = true
        and r.code = 'STAFF'
        and r.AMS_company_id = v_ctx.company_id
        and (urm.AMS_company_id is null or urm.AMS_company_id = v_ctx.company_id)
    );

  if v_staff_login_scope then
    v_mapped_staff := AMS_fn_user_staff_map_staff_id(v_ctx.user_id, v_ctx.company_id);
    if v_mapped_staff is null then
      raise exception 'staff_user_mapping_required';
    end if;
    if p_staff_id is distinct from v_mapped_staff then
      raise exception 'forbidden_self_staff_only';
    end if;
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

  -- Same-company-local-day IN -> OUT rule
  if p_punch_type = 'out' then
    select l.punch_at, (l.punch_at at time zone v_tz)::date
      into v_last_in, v_last_in_day
    from AMS_attendance_log l
    where l.AMS_company_id = v_ctx.company_id
      and l.AMS_staff_id = p_staff_id
      and l.punch_type = 'in'
      and l.punch_at <= v_punch_at
    order by l.punch_at desc
    limit 1;

    if v_last_in is null then
      raise exception 'out_without_in';
    end if;

    if v_last_in_day is distinct from v_punch_day then
      raise exception 'out_not_same_company_day_as_in';
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

grant execute on function AMS_sp_company_attendance_punch(text, uuid, text, uuid, timestamptz, boolean, numeric, uuid) to anon, authenticated, service_role;

commit;
