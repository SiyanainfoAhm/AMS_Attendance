-- Phase 2 / Migration 004: Attendance + shift/automation + compliance + notifications + support + reporting tables

begin;

-- -----------------------------------------------------------------------------
-- Shift and automation
-- -----------------------------------------------------------------------------

create table if not exists AMS_shift_master (
  id uuid primary key,
  AMS_company_id uuid not null,
  code text not null,
  name text not null,
  start_time time not null,
  end_time time not null,
  break_minutes int not null default 0,
  grace_in_minutes int not null default 0,
  grace_out_minutes int not null default 0,
  is_night_shift boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_shift_master_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_shift_master_break_ck check (break_minutes >= 0),
  constraint AMS_shift_master_grace_ck check (grace_in_minutes >= 0 and grace_out_minutes >= 0)
);

create unique index if not exists AMS_shift_master_company_code_uk
  on AMS_shift_master (AMS_company_id, code);

create index if not exists AMS_shift_master_company_active_idx
  on AMS_shift_master (AMS_company_id, is_active);

create trigger AMS_shift_master_set_updated_at_trg
before update on AMS_shift_master
for each row execute function AMS_fn_set_updated_at();

alter table AMS_shift_master enable row level security;

create table if not exists AMS_shift_policy (
  id uuid primary key,
  AMS_company_id uuid not null,
  code text not null,
  name text not null,
  policy_json jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_shift_policy_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade
);

create unique index if not exists AMS_shift_policy_company_code_uk
  on AMS_shift_policy (AMS_company_id, code);

create trigger AMS_shift_policy_set_updated_at_trg
before update on AMS_shift_policy
for each row execute function AMS_fn_set_updated_at();

alter table AMS_shift_policy enable row level security;

create table if not exists AMS_shift_roster (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  AMS_station_id uuid null,
  AMS_shift_master_id uuid not null,
  roster_date date not null,
  roster_source text not null default 'manual',
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_shift_roster_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_shift_roster_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade,
  constraint AMS_shift_roster_station_fk
    foreign key (AMS_station_id) references AMS_station(id) on delete set null,
  constraint AMS_shift_roster_shift_fk
    foreign key (AMS_shift_master_id) references AMS_shift_master(id) on delete restrict,
  constraint AMS_shift_roster_source_ck
    check (roster_source in ('manual','auto','import'))
);

create unique index if not exists AMS_shift_roster_staff_date_uk
  on AMS_shift_roster (AMS_staff_id, roster_date);

create index if not exists AMS_shift_roster_company_date_idx
  on AMS_shift_roster (AMS_company_id, roster_date);

create trigger AMS_shift_roster_set_updated_at_trg
before update on AMS_shift_roster
for each row execute function AMS_fn_set_updated_at();

alter table AMS_shift_roster enable row level security;

create table if not exists AMS_muster_roll (
  id uuid primary key,
  AMS_company_id uuid not null,
  period_start date not null,
  period_end date not null,
  generated_at timestamptz not null default AMS_fn_now_utc(),
  status text not null default 'generated',
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_muster_roll_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_muster_roll_period_ck check (period_start <= period_end),
  constraint AMS_muster_roll_status_ck check (status in ('generated','exported','archived'))
);

create index if not exists AMS_muster_roll_company_period_idx
  on AMS_muster_roll (AMS_company_id, period_start, period_end);

create trigger AMS_muster_roll_set_updated_at_trg
before update on AMS_muster_roll
for each row execute function AMS_fn_set_updated_at();

alter table AMS_muster_roll enable row level security;

create table if not exists AMS_nozzle_allocation (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_nozzle_id uuid not null,
  AMS_staff_id uuid not null,
  allocation_date date not null,
  shift_code text null,
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_nozzle_allocation_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_nozzle_allocation_nozzle_fk
    foreign key (AMS_nozzle_id) references AMS_nozzle(id) on delete cascade,
  constraint AMS_nozzle_allocation_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade
);

create unique index if not exists AMS_nozzle_allocation_nozzle_date_uk
  on AMS_nozzle_allocation (AMS_nozzle_id, allocation_date);

create index if not exists AMS_nozzle_allocation_company_date_idx
  on AMS_nozzle_allocation (AMS_company_id, allocation_date);

create trigger AMS_nozzle_allocation_set_updated_at_trg
before update on AMS_nozzle_allocation
for each row execute function AMS_fn_set_updated_at();

alter table AMS_nozzle_allocation enable row level security;

-- -----------------------------------------------------------------------------
-- Attendance engine
-- -----------------------------------------------------------------------------

create table if not exists AMS_attendance_event_raw (
  id uuid primary key,
  AMS_company_id uuid not null,
  event_source text not null,
  event_payload jsonb not null default '{}'::jsonb,
  captured_at timestamptz not null default AMS_fn_now_utc(),
  received_at timestamptz not null default AMS_fn_now_utc(),
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_attendance_event_raw_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_attendance_event_raw_source_ck
    check (event_source in ('mobile','kiosk','api','import','system'))
);

create index if not exists AMS_attendance_event_raw_company_time_idx
  on AMS_attendance_event_raw (AMS_company_id, captured_at desc);

create trigger AMS_attendance_event_raw_set_updated_at_trg
before update on AMS_attendance_event_raw
for each row execute function AMS_fn_set_updated_at();

alter table AMS_attendance_event_raw enable row level security;

create table if not exists AMS_attendance_log (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  AMS_station_id uuid null,
  AMS_device_id uuid null,
  punch_type text not null,
  punch_at timestamptz not null,
  gps_lat double precision null,
  gps_lng double precision null,
  gps_accuracy_m numeric(10,2) null,
  within_geofence boolean null,
  face_match_score numeric(10,4) null,
  shift_date date null,
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_attendance_log_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_attendance_log_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade,
  constraint AMS_attendance_log_station_fk
    foreign key (AMS_station_id) references AMS_station(id) on delete set null,
  constraint AMS_attendance_log_device_fk
    foreign key (AMS_device_id) references AMS_device(id) on delete set null,
  constraint AMS_attendance_log_punch_type_ck
    check (punch_type in ('in','out','break_in','break_out'))
);

create index if not exists AMS_attendance_log_company_time_idx
  on AMS_attendance_log (AMS_company_id, punch_at desc);

create index if not exists AMS_attendance_log_company_staff_time_idx
  on AMS_attendance_log (AMS_company_id, AMS_staff_id, punch_at desc);

create index if not exists AMS_attendance_log_company_station_time_idx
  on AMS_attendance_log (AMS_company_id, AMS_station_id, punch_at desc);

create trigger AMS_attendance_log_set_updated_at_trg
before update on AMS_attendance_log
for each row execute function AMS_fn_set_updated_at();

alter table AMS_attendance_log enable row level security;

create table if not exists AMS_attendance_exception (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  exception_type text not null,
  exception_date date not null,
  details_json jsonb not null default '{}'::jsonb,
  status text not null default 'open',
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_attendance_exception_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_attendance_exception_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade,
  constraint AMS_attendance_exception_status_ck
    check (status in ('open','resolved','dismissed'))
);

create index if not exists AMS_attendance_exception_company_date_idx
  on AMS_attendance_exception (AMS_company_id, exception_date, status);

create trigger AMS_attendance_exception_set_updated_at_trg
before update on AMS_attendance_exception
for each row execute function AMS_fn_set_updated_at();

alter table AMS_attendance_exception enable row level security;

create table if not exists AMS_attendance_sync_queue (
  id uuid primary key,
  AMS_company_id uuid not null,
  source_device_id uuid null,
  queue_type text not null default 'attendance',
  payload_json jsonb not null,
  status text not null default 'pending',
  attempts int not null default 0,
  last_attempt_at timestamptz null,
  error_message text null,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_attendance_sync_queue_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_attendance_sync_queue_device_fk
    foreign key (source_device_id) references AMS_device(id) on delete set null,
  constraint AMS_attendance_sync_queue_status_ck
    check (status in ('pending','processing','done','failed','dead_letter'))
);

create index if not exists AMS_attendance_sync_queue_company_status_idx
  on AMS_attendance_sync_queue (AMS_company_id, status, created_at);

create trigger AMS_attendance_sync_queue_set_updated_at_trg
before update on AMS_attendance_sync_queue
for each row execute function AMS_fn_set_updated_at();

alter table AMS_attendance_sync_queue enable row level security;

create table if not exists AMS_attendance_audit_request (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_attendance_log_id uuid not null,
  requested_by uuid null,
  requested_at timestamptz not null default AMS_fn_now_utc(),
  reason text null,
  status text not null default 'pending',
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_attendance_audit_request_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_attendance_audit_request_log_fk
    foreign key (AMS_attendance_log_id) references AMS_attendance_log(id) on delete cascade,
  constraint AMS_attendance_audit_request_status_ck
    check (status in ('pending','approved','rejected','cancelled'))
);

create index if not exists AMS_attendance_audit_request_company_status_idx
  on AMS_attendance_audit_request (AMS_company_id, status, requested_at desc);

create trigger AMS_attendance_audit_request_set_updated_at_trg
before update on AMS_attendance_audit_request
for each row execute function AMS_fn_set_updated_at();

alter table AMS_attendance_audit_request enable row level security;

create table if not exists AMS_attendance_audit_response (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_attendance_audit_request_id uuid not null,
  responded_by uuid null,
  responded_at timestamptz not null default AMS_fn_now_utc(),
  decision text not null,
  notes text null,
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_attendance_audit_response_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_attendance_audit_response_request_fk
    foreign key (AMS_attendance_audit_request_id) references AMS_attendance_audit_request(id) on delete cascade,
  constraint AMS_attendance_audit_response_decision_ck
    check (decision in ('approved','rejected'))
);

create unique index if not exists AMS_attendance_audit_response_request_uk
  on AMS_attendance_audit_response (AMS_attendance_audit_request_id);

create trigger AMS_attendance_audit_response_set_updated_at_trg
before update on AMS_attendance_audit_response
for each row execute function AMS_fn_set_updated_at();

alter table AMS_attendance_audit_response enable row level security;

-- -----------------------------------------------------------------------------
-- Leave + compliance
-- -----------------------------------------------------------------------------

create table if not exists AMS_leave_request (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  leave_type text not null,
  start_date date not null,
  end_date date not null,
  reason text null,
  status text not null default 'pending',
  approved_by uuid null,
  approved_at timestamptz null,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_leave_request_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_leave_request_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade,
  constraint AMS_leave_request_dates_ck check (start_date <= end_date),
  constraint AMS_leave_request_status_ck check (status in ('pending','approved','rejected','cancelled'))
);

create index if not exists AMS_leave_request_company_staff_idx
  on AMS_leave_request (AMS_company_id, AMS_staff_id, start_date);

create trigger AMS_leave_request_set_updated_at_trg
before update on AMS_leave_request
for each row execute function AMS_fn_set_updated_at();

alter table AMS_leave_request enable row level security;

create table if not exists AMS_document_compliance (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  document_type text not null,
  status text not null default 'ok',
  expires_at date null,
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_document_compliance_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_document_compliance_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade,
  constraint AMS_document_compliance_status_ck check (status in ('ok','expiring','expired','missing'))
);

create index if not exists AMS_document_compliance_company_status_idx
  on AMS_document_compliance (AMS_company_id, status);

create trigger AMS_document_compliance_set_updated_at_trg
before update on AMS_document_compliance
for each row execute function AMS_fn_set_updated_at();

alter table AMS_document_compliance enable row level security;

create table if not exists AMS_blacklist_whitelist (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  list_type text not null,
  reason text null,
  effective_from date not null default current_date,
  effective_to date null,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_blacklist_whitelist_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_blacklist_whitelist_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade,
  constraint AMS_blacklist_whitelist_type_ck check (list_type in ('blacklist','whitelist'))
);

create index if not exists AMS_blacklist_whitelist_company_type_idx
  on AMS_blacklist_whitelist (AMS_company_id, list_type, is_active);

create trigger AMS_blacklist_whitelist_set_updated_at_trg
before update on AMS_blacklist_whitelist
for each row execute function AMS_fn_set_updated_at();

alter table AMS_blacklist_whitelist enable row level security;

create table if not exists AMS_long_leave_flag (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  flagged_at timestamptz not null default AMS_fn_now_utc(),
  reason text null,
  status text not null default 'open',
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_long_leave_flag_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_long_leave_flag_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade,
  constraint AMS_long_leave_flag_status_ck check (status in ('open','closed','dismissed'))
);

create index if not exists AMS_long_leave_flag_company_status_idx
  on AMS_long_leave_flag (AMS_company_id, status, flagged_at desc);

create trigger AMS_long_leave_flag_set_updated_at_trg
before update on AMS_long_leave_flag
for each row execute function AMS_fn_set_updated_at();

alter table AMS_long_leave_flag enable row level security;

-- -----------------------------------------------------------------------------
-- Notifications
-- -----------------------------------------------------------------------------

create table if not exists AMS_notification (
  id uuid primary key,
  AMS_company_id uuid not null,
  title text not null,
  body text not null,
  channel text not null,
  target_type text not null,
  target_id uuid null,
  status text not null default 'draft',
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_notification_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_notification_channel_ck check (channel in ('push','email','sms','in_app')),
  constraint AMS_notification_status_ck check (status in ('draft','queued','sent','failed'))
);

create index if not exists AMS_notification_company_status_idx
  on AMS_notification (AMS_company_id, status, created_at desc);

create trigger AMS_notification_set_updated_at_trg
before update on AMS_notification
for each row execute function AMS_fn_set_updated_at();

alter table AMS_notification enable row level security;

create table if not exists AMS_notification_queue (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_notification_id uuid not null,
  recipient_type text not null,
  recipient_id uuid null,
  status text not null default 'pending',
  attempts int not null default 0,
  last_attempt_at timestamptz null,
  error_message text null,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_notification_queue_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_notification_queue_notification_fk
    foreign key (AMS_notification_id) references AMS_notification(id) on delete cascade,
  constraint AMS_notification_queue_status_ck check (status in ('pending','processing','done','failed'))
);

create index if not exists AMS_notification_queue_company_status_idx
  on AMS_notification_queue (AMS_company_id, status, created_at);

create trigger AMS_notification_queue_set_updated_at_trg
before update on AMS_notification_queue
for each row execute function AMS_fn_set_updated_at();

alter table AMS_notification_queue enable row level security;

create table if not exists AMS_push_log (
  id uuid primary key,
  AMS_company_id uuid not null,
  recipient text not null,
  provider text null,
  status text not null,
  payload_json jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default AMS_fn_now_utc(),
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_push_log_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade
);

create index if not exists AMS_push_log_company_time_idx
  on AMS_push_log (AMS_company_id, occurred_at desc);

create trigger AMS_push_log_set_updated_at_trg
before update on AMS_push_log
for each row execute function AMS_fn_set_updated_at();

alter table AMS_push_log enable row level security;

-- -----------------------------------------------------------------------------
-- Support / issues
-- -----------------------------------------------------------------------------

create table if not exists AMS_support_ticket (
  id uuid primary key,
  AMS_company_id uuid not null,
  ticket_code text not null,
  title text not null,
  description text null,
  priority text not null default 'medium',
  status text not null default 'open',
  opened_by uuid null,
  assigned_to uuid null,
  opened_at timestamptz not null default AMS_fn_now_utc(),
  due_by timestamptz null,
  closed_at timestamptz null,
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_support_ticket_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_support_ticket_priority_ck check (priority in ('low','medium','high','critical')),
  constraint AMS_support_ticket_status_ck check (status in ('open','in_progress','resolved','closed','cancelled'))
);

create unique index if not exists AMS_support_ticket_company_code_uk
  on AMS_support_ticket (AMS_company_id, ticket_code);

create index if not exists AMS_support_ticket_company_status_idx
  on AMS_support_ticket (AMS_company_id, status, opened_at desc);

create trigger AMS_support_ticket_set_updated_at_trg
before update on AMS_support_ticket
for each row execute function AMS_fn_set_updated_at();

alter table AMS_support_ticket enable row level security;

create table if not exists AMS_issue_log (
  id uuid primary key,
  AMS_company_id uuid not null,
  issue_type text not null,
  severity text not null default 'medium',
  message text not null,
  context_json jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default AMS_fn_now_utc(),
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_issue_log_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_issue_log_severity_ck check (severity in ('low','medium','high','critical'))
);

create index if not exists AMS_issue_log_company_time_idx
  on AMS_issue_log (AMS_company_id, occurred_at desc);

create trigger AMS_issue_log_set_updated_at_trg
before update on AMS_issue_log
for each row execute function AMS_fn_set_updated_at();

alter table AMS_issue_log enable row level security;

-- -----------------------------------------------------------------------------
-- Reporting + dashboard snapshots
-- -----------------------------------------------------------------------------

create table if not exists AMS_report_job (
  id uuid primary key,
  AMS_company_id uuid not null,
  report_code text not null,
  params_json jsonb not null default '{}'::jsonb,
  status text not null default 'queued',
  queued_at timestamptz not null default AMS_fn_now_utc(),
  started_at timestamptz null,
  finished_at timestamptz null,
  error_message text null,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_report_job_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_report_job_status_ck
    check (status in ('queued','running','succeeded','failed','cancelled'))
);

create index if not exists AMS_report_job_company_status_idx
  on AMS_report_job (AMS_company_id, status, queued_at desc);

create trigger AMS_report_job_set_updated_at_trg
before update on AMS_report_job
for each row execute function AMS_fn_set_updated_at();

alter table AMS_report_job enable row level security;

create table if not exists AMS_report_export (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_report_job_id uuid not null,
  file_format text not null,
  storage_bucket text null,
  storage_path text null,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_report_export_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_report_export_job_fk
    foreign key (AMS_report_job_id) references AMS_report_job(id) on delete cascade,
  constraint AMS_report_export_format_ck check (file_format in ('xlsx','csv','pdf'))
);

create index if not exists AMS_report_export_company_idx
  on AMS_report_export (AMS_company_id, created_at desc);

create trigger AMS_report_export_set_updated_at_trg
before update on AMS_report_export
for each row execute function AMS_fn_set_updated_at();

alter table AMS_report_export enable row level security;

create table if not exists AMS_dashboard_snapshot (
  id uuid primary key,
  AMS_company_id uuid not null,
  snapshot_date date not null,
  snapshot_json jsonb not null,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_dashboard_snapshot_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade
);

create unique index if not exists AMS_dashboard_snapshot_company_date_uk
  on AMS_dashboard_snapshot (AMS_company_id, snapshot_date);

create trigger AMS_dashboard_snapshot_set_updated_at_trg
before update on AMS_dashboard_snapshot
for each row execute function AMS_fn_set_updated_at();

alter table AMS_dashboard_snapshot enable row level security;

commit;

