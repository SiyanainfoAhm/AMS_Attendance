-- Phase 7: include durations + last punch type in daily report output
begin;

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

