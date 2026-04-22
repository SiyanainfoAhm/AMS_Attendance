-- Phase 2 / Migration 005: Reporting views scaffolding (placeholders)
-- Note: these are intentionally minimal in Phase 2 and will be expanded in Phase 7.

begin;

create or replace view AMS_vw_station_attendance_summary as
select
  al.AMS_company_id,
  al.AMS_station_id,
  date_trunc('day', al.punch_at) as punch_day,
  count(*) filter (where al.punch_type = 'in') as punch_in_count,
  count(*) filter (where al.punch_type = 'out') as punch_out_count
from AMS_attendance_log al
group by al.AMS_company_id, al.AMS_station_id, date_trunc('day', al.punch_at);

create or replace view AMS_vw_company_productivity_report as
select
  al.AMS_company_id,
  date_trunc('day', al.punch_at) as day,
  count(distinct al.AMS_staff_id) as staff_punched_any
from AMS_attendance_log al
group by al.AMS_company_id, date_trunc('day', al.punch_at);

create or replace view AMS_vw_leave_reconciliation as
select
  lr.AMS_company_id,
  lr.AMS_staff_id,
  lr.leave_type,
  lr.status,
  lr.start_date,
  lr.end_date
from AMS_leave_request lr;

create or replace view AMS_vw_document_expiry_status as
select
  sd.AMS_company_id,
  sd.AMS_staff_id,
  sd.document_type,
  sd.status,
  sd.expires_at
from AMS_staff_document sd;

create or replace view AMS_vw_muster_roll_summary as
select
  mr.AMS_company_id,
  mr.period_start,
  mr.period_end,
  mr.status,
  mr.generated_at
from AMS_muster_roll mr;

create or replace view AMS_vw_repetitive_shift_report as
select
  sr.AMS_company_id,
  sr.AMS_staff_id,
  sr.AMS_shift_master_id,
  count(*) as roster_days
from AMS_shift_roster sr
group by sr.AMS_company_id, sr.AMS_staff_id, sr.AMS_shift_master_id;

create or replace view AMS_vw_repetitive_nozzle_report as
select
  na.AMS_company_id,
  na.AMS_staff_id,
  na.AMS_nozzle_id,
  count(*) as allocation_days
from AMS_nozzle_allocation na
group by na.AMS_company_id, na.AMS_staff_id, na.AMS_nozzle_id;

commit;

