-- Phase 2 / Migration 003: Staff + onboarding + device/kiosk foundations

begin;

-- -----------------------------------------------------------------------------
-- Staff
-- -----------------------------------------------------------------------------

create table if not exists AMS_staff (
  id uuid primary key,
  AMS_company_id uuid not null,
  staff_code text not null,
  full_name text not null,
  mobile text null,
  email text null,
  date_of_birth date null,
  gender text null,
  join_date date null,
  employment_type text null,
  status text not null default 'active',
  is_active boolean not null default true,
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_staff_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_staff_status_ck
    check (status in ('active','inactive','blacklisted','whitelisted','terminated'))
);

create unique index if not exists AMS_staff_company_staff_code_uk
  on AMS_staff (AMS_company_id, staff_code);

create index if not exists AMS_staff_company_status_idx
  on AMS_staff (AMS_company_id, status, is_active);

create index if not exists AMS_staff_company_mobile_idx
  on AMS_staff (AMS_company_id, mobile)
  where mobile is not null;

create trigger AMS_staff_set_updated_at_trg
before update on AMS_staff
for each row execute function AMS_fn_set_updated_at();

alter table AMS_staff enable row level security;

create table if not exists AMS_staff_kyc (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  kyc_status text not null default 'pending',
  kyc_json jsonb not null default '{}'::jsonb,
  verified_at timestamptz null,
  verified_by uuid null,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_staff_kyc_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_staff_kyc_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade,
  constraint AMS_staff_kyc_status_ck
    check (kyc_status in ('pending','verified','rejected'))
);

create unique index if not exists AMS_staff_kyc_staff_uk
  on AMS_staff_kyc (AMS_staff_id);

create index if not exists AMS_staff_kyc_company_status_idx
  on AMS_staff_kyc (AMS_company_id, kyc_status);

create trigger AMS_staff_kyc_set_updated_at_trg
before update on AMS_staff_kyc
for each row execute function AMS_fn_set_updated_at();

alter table AMS_staff_kyc enable row level security;

create table if not exists AMS_staff_document (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  document_type text not null,
  document_number text null,
  storage_bucket text null,
  storage_path text null,
  status text not null default 'pending',
  issued_at date null,
  expires_at date null,
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_staff_document_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_staff_document_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade,
  constraint AMS_staff_document_status_ck
    check (status in ('pending','verified','rejected','expired'))
);

create index if not exists AMS_staff_document_company_staff_idx
  on AMS_staff_document (AMS_company_id, AMS_staff_id, document_type);

create index if not exists AMS_staff_document_company_expiry_idx
  on AMS_staff_document (AMS_company_id, expires_at)
  where expires_at is not null;

create trigger AMS_staff_document_set_updated_at_trg
before update on AMS_staff_document
for each row execute function AMS_fn_set_updated_at();

alter table AMS_staff_document enable row level security;

create table if not exists AMS_staff_face_template (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  template_version text not null,
  template_ciphertext bytea not null,
  template_nonce bytea not null,
  template_kid text not null,
  enrolled_at timestamptz not null default AMS_fn_now_utc(),
  enrolled_by uuid null,
  is_active boolean not null default true,
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_staff_face_template_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_staff_face_template_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade
);

create unique index if not exists AMS_staff_face_template_staff_active_uk
  on AMS_staff_face_template (AMS_staff_id)
  where is_active = true;

create index if not exists AMS_staff_face_template_company_idx
  on AMS_staff_face_template (AMS_company_id, enrolled_at desc);

create trigger AMS_staff_face_template_set_updated_at_trg
before update on AMS_staff_face_template
for each row execute function AMS_fn_set_updated_at();

alter table AMS_staff_face_template enable row level security;

create table if not exists AMS_staff_station_map (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  AMS_station_id uuid not null,
  is_primary boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_staff_station_map_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_staff_station_map_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade,
  constraint AMS_staff_station_map_station_fk
    foreign key (AMS_station_id) references AMS_station(id) on delete cascade
);

alter table AMS_staff_station_map
  add constraint AMS_staff_station_map_uk unique (AMS_staff_id, AMS_station_id);

create index if not exists AMS_staff_station_map_company_station_idx
  on AMS_staff_station_map (AMS_company_id, AMS_station_id, is_active);

create trigger AMS_staff_station_map_set_updated_at_trg
before update on AMS_staff_station_map
for each row execute function AMS_fn_set_updated_at();

alter table AMS_staff_station_map enable row level security;

create table if not exists AMS_staff_status_history (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_staff_id uuid not null,
  from_status text null,
  to_status text not null,
  reason text null,
  changed_at timestamptz not null default AMS_fn_now_utc(),
  changed_by uuid null,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_staff_status_history_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_staff_status_history_staff_fk
    foreign key (AMS_staff_id) references AMS_staff(id) on delete cascade
);

create index if not exists AMS_staff_status_history_company_staff_idx
  on AMS_staff_status_history (AMS_company_id, AMS_staff_id, changed_at desc);

create trigger AMS_staff_status_history_set_updated_at_trg
before update on AMS_staff_status_history
for each row execute function AMS_fn_set_updated_at();

alter table AMS_staff_status_history enable row level security;

-- -----------------------------------------------------------------------------
-- Device / kiosk
-- -----------------------------------------------------------------------------

create table if not exists AMS_device (
  id uuid primary key,
  AMS_company_id uuid not null,
  device_code text not null,
  device_type text not null,
  display_name text null,
  platform text null,
  os_version text null,
  app_version text null,
  last_seen_at timestamptz null,
  is_active boolean not null default true,
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_device_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_device_type_ck
    check (device_type in ('mobile','kiosk','tablet','web'))
);

create unique index if not exists AMS_device_company_device_code_uk
  on AMS_device (AMS_company_id, device_code);

create index if not exists AMS_device_company_type_idx
  on AMS_device (AMS_company_id, device_type, is_active);

create trigger AMS_device_set_updated_at_trg
before update on AMS_device
for each row execute function AMS_fn_set_updated_at();

alter table AMS_device enable row level security;

create table if not exists AMS_kiosk_device (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_device_id uuid not null,
  AMS_station_id uuid not null,
  activation_code text null,
  activated_at timestamptz null,
  activated_by uuid null,
  is_active boolean not null default true,
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_kiosk_device_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_kiosk_device_device_fk
    foreign key (AMS_device_id) references AMS_device(id) on delete cascade,
  constraint AMS_kiosk_device_station_fk
    foreign key (AMS_station_id) references AMS_station(id) on delete cascade
);

alter table AMS_kiosk_device
  add constraint AMS_kiosk_device_device_uk unique (AMS_device_id);

create index if not exists AMS_kiosk_device_company_station_idx
  on AMS_kiosk_device (AMS_company_id, AMS_station_id, is_active);

create trigger AMS_kiosk_device_set_updated_at_trg
before update on AMS_kiosk_device
for each row execute function AMS_fn_set_updated_at();

alter table AMS_kiosk_device enable row level security;

create table if not exists AMS_device_health_log (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_device_id uuid not null,
  status text not null,
  battery_percent int null,
  network_type text null,
  meta_json jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default AMS_fn_now_utc(),
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_device_health_log_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_device_health_log_device_fk
    foreign key (AMS_device_id) references AMS_device(id) on delete cascade,
  constraint AMS_device_health_log_battery_ck
    check (battery_percent is null or (battery_percent >= 0 and battery_percent <= 100))
);

create index if not exists AMS_device_health_log_company_device_time_idx
  on AMS_device_health_log (AMS_company_id, AMS_device_id, occurred_at desc);

create trigger AMS_device_health_log_set_updated_at_trg
before update on AMS_device_health_log
for each row execute function AMS_fn_set_updated_at();

alter table AMS_device_health_log enable row level security;

commit;

