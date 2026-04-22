-- Link login users to staff records (for self-service punch) + enforce self-only punch for STAFF role

begin;

create table if not exists AMS_user_staff_map (
  id uuid primary key default gen_random_uuid(),
  AMS_company_id uuid not null,
  AMS_user_id uuid not null,
  AMS_staff_id uuid not null,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_user_staff_map_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_user_staff_map_user_fk
    foreign key (AMS_user_id) references AMS_user(id) on delete cascade,
  constraint AMS_user_staff_map_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade
);

create unique index if not exists AMS_user_staff_map_user_company_uk
  on AMS_user_staff_map (ams_user_id, ams_company_id);

create index if not exists AMS_user_staff_map_company_staff_idx
  on AMS_user_staff_map (ams_company_id, ams_staff_id)
  where is_active = true;

create trigger AMS_user_staff_map_set_updated_at_trg
before update on AMS_user_staff_map
for each row execute function AMS_fn_set_updated_at();

alter table AMS_user_staff_map enable row level security;

create or replace function AMS_fn_user_staff_map_staff_id(p_user_id uuid, p_company_id uuid)
returns uuid
language sql
stable
as $$
  select m.AMS_staff_id
  from AMS_user_staff_map m
  where m.AMS_user_id = p_user_id
    and m.AMS_company_id = p_company_id
    and m.is_active = true
  limit 1;
$$;

create or replace function AMS_sp_company_user_staff_map_upsert(
  p_access_token text,
  p_user_id uuid,
  p_staff_id uuid,
  p_is_active boolean default true
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_ctx record;
begin
  select * into v_ctx from AMS_fn_require_company_context(p_access_token) limit 1;
  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_STAFF_WRITE') then
    raise exception 'forbidden';
  end if;

  if p_user_id is null or p_staff_id is null then
    raise exception 'invalid_body';
  end if;

  if not exists (
    select 1
    from AMS_user_company_map ucm
    join AMS_company c on c.id = ucm.AMS_company_id
    where ucm.AMS_user_id = p_user_id
      and ucm.AMS_company_id = v_ctx.company_id
      and ucm.is_active = true
      and c.is_active = true
  ) then
    raise exception 'user_not_in_company';
  end if;

  if not exists (
    select 1
    from AMS_staff s
    where s.id = p_staff_id
      and s.AMS_company_id = v_ctx.company_id
      and s.is_active = true
  ) then
    raise exception 'staff_not_found';
  end if;

  insert into AMS_user_staff_map (
    id, AMS_company_id, AMS_user_id, AMS_staff_id, is_active,
    created_at, updated_at, created_by, updated_by
  )
  values (
    gen_random_uuid(), v_ctx.company_id, p_user_id, p_staff_id, coalesce(p_is_active, true),
    v_now, v_now, v_ctx.user_id, v_ctx.user_id
  )
  on conflict (ams_user_id, ams_company_id) do update
  set
    ams_staff_id = excluded.ams_staff_id,
    is_active = excluded.is_active,
    updated_at = v_now,
    updated_by = v_ctx.user_id;

  insert into AMS_audit_log (
    id, AMS_company_id, actor_user_id, action_code, entity_type, entity_id, details_json,
    occurred_at, created_at, updated_at, created_by, updated_by
  )
  values (
    gen_random_uuid(), v_ctx.company_id, v_ctx.user_id, 'COMPANY_USER_STAFF_MAP_UPSERT',
    'AMS_user_staff_map', p_user_id,
    jsonb_build_object('mapped_user_id', p_user_id, 'staff_id', p_staff_id, 'is_active', coalesce(p_is_active, true)),
    v_now, v_now, v_now, v_ctx.user_id, v_ctx.user_id
  );

  return jsonb_build_object('user_id', p_user_id, 'staff_id', p_staff_id);
end;
$$;

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
  v_mapped_staff uuid;
  v_staff_login_scope boolean;
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
