-- Phase 8: Audit cases (staff-facing remediation for anomalies like missing punches)
begin;

-- -----------------------------------------------------------------------------
-- Audit Case
-- -----------------------------------------------------------------------------

create table if not exists AMS_audit_case (
  id uuid primary key default gen_random_uuid(),
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  case_type text not null,
  status text not null default 'open',
  shift_date date not null,
  title text not null,
  description text null,
  payload_json jsonb not null default '{}'::jsonb,
  resolved_at timestamptz null,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_audit_case_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_audit_case_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade,
  constraint AMS_audit_case_status_ck
    check (status in ('open','resolved','dismissed')),
  constraint AMS_audit_case_type_ck
    check (case_type in ('missing_out','missing_break_out'))
);

create index if not exists AMS_audit_case_company_status_idx
  on AMS_audit_case (AMS_company_id, status, created_at desc);

create index if not exists AMS_audit_case_staff_status_idx
  on AMS_audit_case (AMS_staff_id, status, created_at desc);

-- Uniqueness for (company, staff, day, type) so generator can use ON CONFLICT safely.
-- Use a named UNIQUE CONSTRAINT (not just an index) to avoid partial-index mismatch issues.
do $$
begin
  -- If an older partial index exists from a previous attempt, drop it.
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'i'
      and c.relname = 'ams_audit_case_company_staff_day_type_uk'
  ) then
    execute 'drop index if exists AMS_audit_case_company_staff_day_type_uk';
  end if;

  -- Enforce NOT NULL shift_date (if table existed before).
  begin
    execute 'alter table AMS_audit_case alter column shift_date set not null';
  exception when others then
    -- ignore if column already not null or table not created yet
    null;
  end;

  -- Add unique constraint if missing.
  if not exists (
    select 1
    from pg_constraint
    where conname = 'AMS_audit_case_company_staff_day_type_uk'
  ) then
    execute 'alter table AMS_audit_case add constraint AMS_audit_case_company_staff_day_type_uk unique (AMS_company_id, AMS_staff_id, shift_date, case_type)';
  end if;
end;
$$;

drop trigger if exists AMS_audit_case_set_updated_at_trg on AMS_audit_case;
create trigger AMS_audit_case_set_updated_at_trg
before update on AMS_audit_case
for each row execute function AMS_fn_set_updated_at();

alter table AMS_audit_case enable row level security;

-- -----------------------------------------------------------------------------
-- Audit Response (from staff)
-- -----------------------------------------------------------------------------

create table if not exists AMS_audit_response (
  id uuid primary key default gen_random_uuid(),
  AMS_company_id uuid not null,
  AMS_audit_case_id uuid not null,
  AMS_user_id uuid not null,
  response_text text not null,
  payload_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_audit_response_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_audit_response_case_fk
    foreign key (AMS_audit_case_id) references AMS_audit_case(id) on delete cascade,
  constraint AMS_audit_response_user_fk
    foreign key (AMS_user_id) references AMS_user(id) on delete cascade
);

create index if not exists AMS_audit_response_case_idx
  on AMS_audit_response (AMS_audit_case_id, created_at desc);

drop trigger if exists AMS_audit_response_set_updated_at_trg on AMS_audit_response;
create trigger AMS_audit_response_set_updated_at_trg
before update on AMS_audit_response
for each row execute function AMS_fn_set_updated_at();

alter table AMS_audit_response enable row level security;

-- -----------------------------------------------------------------------------
-- Generator: create audit cases for missing punches from daily rollups
-- -----------------------------------------------------------------------------

create or replace function AMS_fn_audit_generate_missing_attendance_from_rollup(
  p_company_id uuid,
  p_from date,
  p_to date,
  p_staff_id uuid default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows int := 0;
  v_more int := 0;
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

  -- Missing OUT
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
  )
  insert into AMS_audit_case (
    AMS_company_id, AMS_staff_id, case_type, status, shift_date, title, description, payload_json,
    created_at, updated_at, created_by, updated_by
  )
  select
    s.AMS_company_id, s.AMS_staff_id, s.case_type, 'open', s.shift_date, s.title, s.description, s.payload_json,
    AMS_fn_now_utc(), AMS_fn_now_utc(), null, null
  from src s
  on conflict (AMS_company_id, AMS_staff_id, shift_date, case_type) do nothing;

  get diagnostics v_rows = row_count;

  -- Missing BREAK_OUT
  with src2 as (
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
  )
  insert into AMS_audit_case (
    AMS_company_id, AMS_staff_id, case_type, status, shift_date, title, description, payload_json,
    created_at, updated_at, created_by, updated_by
  )
  select
    s.AMS_company_id, s.AMS_staff_id, s.case_type, 'open', s.shift_date, s.title, s.description, s.payload_json,
    AMS_fn_now_utc(), AMS_fn_now_utc(), null, null
  from src2 s
  on conflict (AMS_company_id, AMS_staff_id, shift_date, case_type) do nothing;

  get diagnostics v_more = row_count;
  v_rows := v_rows + v_more;
  return v_rows;
end;
$$;

grant execute on function AMS_fn_audit_generate_missing_attendance_from_rollup(uuid, date, date, uuid) to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Staff RPCs
-- -----------------------------------------------------------------------------

create or replace function AMS_sp_staff_audit_list(
  p_access_token text,
  p_status text default 'open',
  p_limit int default 50
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_staff_id uuid;
  v_lim int := greatest(1, least(coalesce(p_limit, 50), 200));
  v_status text := coalesce(nullif(trim(p_status), ''), 'open');
  v_rows int;
  v_from date := (AMS_fn_now_utc()::date - 30);
  v_to date := AMS_fn_now_utc()::date;
begin
  select * into v_ctx from AMS_fn_require_company_context(p_access_token) limit 1;
  v_staff_id := AMS_fn_user_staff_map_staff_id(v_ctx.user_id, v_ctx.company_id);
  if v_staff_id is null then
    raise exception 'staff_user_mapping_required';
  end if;

  -- Best-effort: create audit cases for last 30 days from existing rollups.
  v_rows := AMS_fn_audit_generate_missing_attendance_from_rollup(v_ctx.company_id, v_from, v_to, v_staff_id);

  return jsonb_build_object(
    'ok', true,
    'generated', v_rows,
    'items', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
      from (
        select
          c.id,
          c.case_type,
          c.status,
          c.shift_date,
          c.title,
          c.description,
          c.payload_json,
          c.created_at,
          c.resolved_at
        from AMS_audit_case c
        where c.AMS_company_id = v_ctx.company_id
          and c.AMS_staff_id = v_staff_id
          and (v_status is null or c.status = v_status)
        order by c.created_at desc
        limit v_lim
      ) x
    )
  );
end;
$$;

grant execute on function AMS_sp_staff_audit_list(text, text, int) to anon, authenticated, service_role;

create or replace function AMS_sp_staff_audit_submit_response(
  p_access_token text,
  p_case_id uuid,
  p_response_text text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_staff_id uuid;
  v_case record;
  v_now timestamptz := AMS_fn_now_utc();
begin
  select * into v_ctx from AMS_fn_require_company_context(p_access_token) limit 1;
  v_staff_id := AMS_fn_user_staff_map_staff_id(v_ctx.user_id, v_ctx.company_id);
  if v_staff_id is null then
    raise exception 'staff_user_mapping_required';
  end if;
  if p_case_id is null then
    raise exception 'case_id_required';
  end if;
  if p_response_text is null or length(trim(p_response_text)) = 0 then
    raise exception 'response_required';
  end if;

  select * into v_case
  from AMS_audit_case c
  where c.id = p_case_id
    and c.AMS_company_id = v_ctx.company_id
    and c.AMS_staff_id = v_staff_id
  limit 1;

  if v_case.id is null then
    raise exception 'case_not_found';
  end if;
  if v_case.status <> 'open' then
    raise exception 'case_not_open';
  end if;

  insert into AMS_audit_response (
    AMS_company_id, AMS_audit_case_id, AMS_user_id, response_text, payload_json,
    created_at, updated_at, created_by, updated_by
  )
  values (
    v_ctx.company_id, p_case_id, v_ctx.user_id, trim(p_response_text), '{}'::jsonb,
    v_now, v_now, v_ctx.user_id, v_ctx.user_id
  );

  update AMS_audit_case
  set
    status = 'resolved',
    resolved_at = v_now,
    updated_at = v_now,
    updated_by = v_ctx.user_id
  where id = p_case_id;

  return jsonb_build_object('ok', true, 'case_id', p_case_id, 'status', 'resolved');
end;
$$;

grant execute on function AMS_sp_staff_audit_submit_response(text, uuid, text) to anon, authenticated, service_role;

commit;

