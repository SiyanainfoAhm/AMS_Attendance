-- Phase 8b: Admin audit dashboard RPCs + richer payloads
begin;

-- -----------------------------------------------------------------------------
-- Extend generator payload to include station context (best-effort)
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
      r.last_station_id,
      'missing_out'::text as case_type,
      'Missing OUT punch'::text as title,
      'You have an open session for this day. Please confirm what happened and provide details.'::text as description,
      jsonb_build_object(
        'shift_date', r.shift_date,
        'last_punch_type', r.last_punch_type,
        'first_in_at', r.first_in_at,
        'last_punch_at', r.last_punch_at,
        'last_station_id', r.last_station_id,
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
      r.last_station_id,
      'missing_break_out'::text as case_type,
      'Missing Break OUT punch'::text as title,
      'You have an open break for this day. Please confirm what happened and provide details.'::text as description,
      jsonb_build_object(
        'shift_date', r.shift_date,
        'last_punch_type', r.last_punch_type,
        'first_in_at', r.first_in_at,
        'last_punch_at', r.last_punch_at,
        'last_station_id', r.last_station_id,
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
-- Admin/company RPCs
-- -----------------------------------------------------------------------------

create or replace function AMS_sp_company_audit_list(
  p_access_token text,
  p_status text default 'open',
  p_case_type text default null,
  p_from date default null,
  p_to date default null,
  p_staff_id uuid default null,
  p_station_id uuid default null,
  p_limit int default 200
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_lim int := greatest(1, least(coalesce(p_limit, 200), 500));
  v_status text := coalesce(nullif(trim(p_status), ''), 'open');
  v_type text := nullif(trim(coalesce(p_case_type, '')), '');
  v_from date := coalesce(p_from, (AMS_fn_now_utc()::date - 30));
  v_to date := coalesce(p_to, AMS_fn_now_utc()::date);
begin
  select * into v_ctx from AMS_fn_require_company_context(p_access_token) limit 1;

  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ATTENDANCE_READ') then
    raise exception 'forbidden';
  end if;

  -- Best-effort generate from rollups so dashboard has cases even without manual generation.
  perform AMS_fn_audit_generate_missing_attendance_from_rollup(v_ctx.company_id, v_from, v_to, p_staff_id);

  return jsonb_build_object(
    'ok', true,
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
          c.resolved_at,
          c.AMS_staff_id as staff_id,
          s.staff_code,
          s.full_name,
          c.updated_at,
          c.updated_by,
          st.id as station_id,
          st.code as station_code,
          st.name as station_name
        from AMS_audit_case c
        join AMS_staff s on s.id = c.AMS_staff_id
        left join AMS_station st on st.id = coalesce((c.payload_json->>'last_station_id')::uuid, null)
        where c.AMS_company_id = v_ctx.company_id
          and (v_status is null or c.status = v_status)
          and (v_type is null or c.case_type = v_type)
          and c.shift_date between v_from and v_to
          and (p_staff_id is null or c.AMS_staff_id = p_staff_id)
          and (p_station_id is null or st.id = p_station_id)
        order by c.created_at desc
        limit v_lim
      ) x
    )
  );
end;
$$;

grant execute on function AMS_sp_company_audit_list(text, text, text, date, date, uuid, uuid, int) to anon, authenticated, service_role;

create or replace function AMS_sp_company_audit_set_status(
  p_access_token text,
  p_case_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ctx record;
  v_now timestamptz := AMS_fn_now_utc();
  v_status text := coalesce(nullif(trim(p_status), ''), '');
begin
  select * into v_ctx from AMS_fn_require_company_context(p_access_token) limit 1;

  if not AMS_fn_user_has_permission(v_ctx.user_id, v_ctx.company_id, 'COMPANY_ATTENDANCE_WRITE') then
    raise exception 'forbidden';
  end if;

  if p_case_id is null then
    raise exception 'case_id_required';
  end if;
  if v_status not in ('open','resolved','dismissed') then
    raise exception 'invalid_status';
  end if;

  update AMS_audit_case
  set
    status = v_status,
    resolved_at = case when v_status = 'resolved' then v_now else resolved_at end,
    updated_at = v_now,
    updated_by = v_ctx.user_id
  where id = p_case_id
    and AMS_company_id = v_ctx.company_id;

  if not found then
    raise exception 'case_not_found';
  end if;

  return jsonb_build_object('ok', true, 'case_id', p_case_id, 'status', v_status);
end;
$$;

grant execute on function AMS_sp_company_audit_set_status(text, uuid, text) to anon, authenticated, service_role;

commit;

