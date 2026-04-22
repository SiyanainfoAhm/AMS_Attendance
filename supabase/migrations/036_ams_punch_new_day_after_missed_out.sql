-- If same-day OUT was not punched, that day stays open in reporting/audit (missing_out).
-- Next calendar day may start a fresh IN→OUT flow without blocking on a retroactive OUT.

begin;

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
  v_last_in_shift_day date;
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

  -- OUT closes the latest open IN (no OUT between that IN and this punch).
  -- shift_date follows the IN row’s calendar day so a late OUT can still book to the correct shift day.
  if p_punch_type = 'out' then
    select i.punch_at, coalesce(i.shift_date, (i.punch_at at time zone v_tz)::date)
      into v_last_in, v_last_in_shift_day
    from AMS_attendance_log i
    where i.AMS_company_id = v_ctx.company_id
      and i.AMS_staff_id = p_staff_id
      and i.punch_type = 'in'
      and i.punch_at <= v_punch_at
      and not exists (
        select 1
        from AMS_attendance_log o
        where o.AMS_company_id = i.AMS_company_id
          and o.AMS_staff_id = i.AMS_staff_id
          and o.punch_type = 'out'
          and o.punch_at > i.punch_at
          and o.punch_at < v_punch_at
      )
    order by i.punch_at desc
    limit 1;

    if v_last_in is null then
      raise exception 'out_without_in';
    end if;

    v_shift_date := v_last_in_shift_day;
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
