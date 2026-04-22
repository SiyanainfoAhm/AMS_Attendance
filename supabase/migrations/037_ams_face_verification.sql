-- Phase 10: Face verification (AWS Rekognition) + selfie evidence storage for audit
begin;

-- -----------------------------------------------------------------------------
-- Company settings: Rekognition configuration
-- -----------------------------------------------------------------------------

alter table AMS_company_settings
  add column if not exists rekognition_region text null,
  add column if not exists rekognition_collection_id text null;

-- -----------------------------------------------------------------------------
-- Staff face enrollment
-- -----------------------------------------------------------------------------

create table if not exists AMS_staff_face_profile (
  id uuid primary key default gen_random_uuid(),
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  status text not null default 'pending',
  enrolled_face_count int not null default 0,
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_staff_face_profile_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_staff_face_profile_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade,
  constraint AMS_staff_face_profile_status_ck
    check (status in ('pending','active','disabled'))
);

alter table AMS_staff_face_profile
  add constraint AMS_staff_face_profile_company_staff_uk unique (AMS_company_id, AMS_staff_id);

drop trigger if exists AMS_staff_face_profile_set_updated_at_trg on AMS_staff_face_profile;
create trigger AMS_staff_face_profile_set_updated_at_trg
before update on AMS_staff_face_profile
for each row execute function AMS_fn_set_updated_at();

alter table AMS_staff_face_profile enable row level security;

create table if not exists AMS_staff_face_vector (
  id uuid primary key default gen_random_uuid(),
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  rekognition_face_id text not null,
  is_active boolean not null default true,
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_staff_face_vector_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_staff_face_vector_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade
);

create index if not exists AMS_staff_face_vector_company_staff_idx
  on AMS_staff_face_vector (AMS_company_id, AMS_staff_id, is_active, created_at desc);

alter table AMS_staff_face_vector
  add constraint AMS_staff_face_vector_company_staff_face_uk unique (AMS_company_id, AMS_staff_id, rekognition_face_id);

drop trigger if exists AMS_staff_face_vector_set_updated_at_trg on AMS_staff_face_vector;
create trigger AMS_staff_face_vector_set_updated_at_trg
before update on AMS_staff_face_vector
for each row execute function AMS_fn_set_updated_at();

alter table AMS_staff_face_vector enable row level security;

-- -----------------------------------------------------------------------------
-- Attendance log: face verification metadata + selfie evidence key
-- -----------------------------------------------------------------------------

alter table AMS_attendance_log
  add column if not exists face_required boolean not null default true,
  add column if not exists face_provider text not null default 'aws_rekognition',
  add column if not exists face_verified boolean null,
  add column if not exists face_liveness_passed boolean null,
  add column if not exists face_error_code text null,
  add column if not exists face_checked_at timestamptz null,
  add column if not exists selfie_object_key text null;

create index if not exists AMS_attendance_log_company_face_idx
  on AMS_attendance_log (AMS_company_id, face_verified, punch_at desc);

-- -----------------------------------------------------------------------------
-- Audit case types: add face_verification_failed
-- -----------------------------------------------------------------------------

-- Drop existing check constraint if present (older migrations created it without quoting, so it's lowercase in catalog).
alter table AMS_audit_case drop constraint if exists AMS_audit_case_type_ck;
alter table AMS_audit_case drop constraint if exists ams_audit_case_type_ck;

alter table AMS_audit_case
  add constraint AMS_audit_case_type_ck
    check (case_type in ('missing_out','missing_break_out','face_verification_failed'));

-- -----------------------------------------------------------------------------
-- Storage: bucket for audit selfies (private). Evidence is accessed via signed URLs.
-- -----------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from storage.buckets where id = 'attendance-audit-selfies') then
    insert into storage.buckets (id, name, public)
    values ('attendance-audit-selfies', 'attendance-audit-selfies', false);
  end if;
end;
$$;

commit;

