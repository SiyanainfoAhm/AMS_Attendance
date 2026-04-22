-- Phase 2 / Migration 002: Organization structure
-- Tables: AMS_zone, AMS_branch, AMS_station, AMS_geofence, AMS_vendor, AMS_nozzle

begin;

-- -----------------------------------------------------------------------------
-- Zone
-- -----------------------------------------------------------------------------

create table if not exists AMS_zone (
  id uuid primary key,
  AMS_company_id uuid not null,
  code text not null,
  name text not null,
  description text null,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_zone_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade
);

create unique index if not exists AMS_zone_company_code_uk
  on AMS_zone (AMS_company_id, code);

create index if not exists AMS_zone_company_active_idx
  on AMS_zone (AMS_company_id, is_active);

create trigger AMS_zone_set_updated_at_trg
before update on AMS_zone
for each row execute function AMS_fn_set_updated_at();

alter table AMS_zone enable row level security;

-- -----------------------------------------------------------------------------
-- Branch
-- -----------------------------------------------------------------------------

create table if not exists AMS_branch (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_zone_id uuid null,
  code text not null,
  name text not null,
  address_json jsonb not null default '{}'::jsonb,
  latitude double precision null,
  longitude double precision null,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_branch_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_branch_zone_fk
    foreign key (AMS_zone_id) references AMS_zone(id) on delete set null
);

create unique index if not exists AMS_branch_company_code_uk
  on AMS_branch (AMS_company_id, code);

create index if not exists AMS_branch_company_zone_idx
  on AMS_branch (AMS_company_id, AMS_zone_id);

create index if not exists AMS_branch_company_active_idx
  on AMS_branch (AMS_company_id, is_active);

create trigger AMS_branch_set_updated_at_trg
before update on AMS_branch
for each row execute function AMS_fn_set_updated_at();

alter table AMS_branch enable row level security;

-- -----------------------------------------------------------------------------
-- Station (site/station where attendance happens)
-- -----------------------------------------------------------------------------

create table if not exists AMS_station (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_zone_id uuid null,
  AMS_branch_id uuid null,
  code text not null,
  name text not null,
  address_json jsonb not null default '{}'::jsonb,
  latitude double precision null,
  longitude double precision null,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_station_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_station_zone_fk
    foreign key (AMS_zone_id) references AMS_zone(id) on delete set null,
  constraint AMS_station_branch_fk
    foreign key (AMS_branch_id) references AMS_branch(id) on delete set null
);

create unique index if not exists AMS_station_company_code_uk
  on AMS_station (AMS_company_id, code);

create index if not exists AMS_station_company_zone_idx
  on AMS_station (AMS_company_id, AMS_zone_id);

create index if not exists AMS_station_company_branch_idx
  on AMS_station (AMS_company_id, AMS_branch_id);

create index if not exists AMS_station_company_active_idx
  on AMS_station (AMS_company_id, is_active);

create trigger AMS_station_set_updated_at_trg
before update on AMS_station
for each row execute function AMS_fn_set_updated_at();

alter table AMS_station enable row level security;

-- -----------------------------------------------------------------------------
-- Geofence
-- -----------------------------------------------------------------------------

create table if not exists AMS_geofence (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_station_id uuid null,
  code text not null,
  name text not null,
  geofence_type text not null default 'circle',
  -- For 'circle': center_lat/center_lng + radius_m
  center_lat double precision null,
  center_lng double precision null,
  radius_m numeric(10,2) null,
  -- For 'polygon': polygon_json
  polygon_json jsonb not null default '[]'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_geofence_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_geofence_station_fk
    foreign key (AMS_station_id) references AMS_station(id) on delete set null,
  constraint AMS_geofence_type_ck
    check (geofence_type in ('circle','polygon')),
  constraint AMS_geofence_circle_ck
    check (
      (geofence_type <> 'circle')
      or (center_lat is not null and center_lng is not null and radius_m is not null and radius_m > 0)
    )
);

create unique index if not exists AMS_geofence_company_code_uk
  on AMS_geofence (AMS_company_id, code);

create index if not exists AMS_geofence_company_station_idx
  on AMS_geofence (AMS_company_id, AMS_station_id, is_active);

create trigger AMS_geofence_set_updated_at_trg
before update on AMS_geofence
for each row execute function AMS_fn_set_updated_at();

alter table AMS_geofence enable row level security;

-- -----------------------------------------------------------------------------
-- Vendor
-- -----------------------------------------------------------------------------

create table if not exists AMS_vendor (
  id uuid primary key,
  AMS_company_id uuid not null,
  code text not null,
  name text not null,
  contact_json jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_vendor_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade
);

create unique index if not exists AMS_vendor_company_code_uk
  on AMS_vendor (AMS_company_id, code);

create index if not exists AMS_vendor_company_active_idx
  on AMS_vendor (AMS_company_id, is_active);

create trigger AMS_vendor_set_updated_at_trg
before update on AMS_vendor
for each row execute function AMS_fn_set_updated_at();

alter table AMS_vendor enable row level security;

-- -----------------------------------------------------------------------------
-- Nozzle (station equipment concept)
-- -----------------------------------------------------------------------------

create table if not exists AMS_nozzle (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_station_id uuid not null,
  code text not null,
  name text not null,
  meta_json jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_nozzle_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_nozzle_station_fk
    foreign key (AMS_station_id) references AMS_station(id) on delete cascade
);

create unique index if not exists AMS_nozzle_station_code_uk
  on AMS_nozzle (AMS_station_id, code);

create index if not exists AMS_nozzle_company_station_idx
  on AMS_nozzle (AMS_company_id, AMS_station_id, is_active);

create trigger AMS_nozzle_set_updated_at_trg
before update on AMS_nozzle
for each row execute function AMS_fn_set_updated_at();

alter table AMS_nozzle enable row level security;

commit;

