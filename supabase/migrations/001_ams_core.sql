-- Phase 2 / Migration 001: Core platform + custom auth + RBAC + audit
-- Rules:
-- - Every DB object is prefixed with AMS_
-- - Supabase Auth is not used (custom auth tables + APIs)
-- - RLS enabled (no policies yet) to prevent direct anon access

begin;

-- Extensions (object names are not controllable; allowed exception)
create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Shared helpers
-- -----------------------------------------------------------------------------

create or replace function AMS_fn_now_utc()
returns timestamptz
language sql
stable
as $$
  select now();
$$;

create or replace function AMS_fn_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := AMS_fn_now_utc();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Company (tenant)
-- -----------------------------------------------------------------------------

create table if not exists AMS_company (
  id uuid primary key,
  code text not null,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null
);

alter table AMS_company
  add constraint AMS_company_code_uk unique (code);

create index if not exists AMS_company_is_active_idx
  on AMS_company (is_active);

create trigger AMS_company_set_updated_at_trg
before update on AMS_company
for each row execute function AMS_fn_set_updated_at();

alter table AMS_company enable row level security;

create table if not exists AMS_company_settings (
  id uuid primary key,
  AMS_company_id uuid not null,
  timezone text not null default 'Asia/Kolkata',
  branding_json jsonb not null default '{}'::jsonb,
  attendance_rules_json jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_company_settings_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade
);

alter table AMS_company_settings
  add constraint AMS_company_settings_company_uk unique (AMS_company_id);

create index if not exists AMS_company_settings_company_idx
  on AMS_company_settings (AMS_company_id);

create trigger AMS_company_settings_set_updated_at_trg
before update on AMS_company_settings
for each row execute function AMS_fn_set_updated_at();

alter table AMS_company_settings enable row level security;

create table if not exists AMS_company_subscription (
  id uuid primary key,
  AMS_company_id uuid not null,
  plan_code text not null,
  status text not null,
  start_at timestamptz null,
  end_at timestamptz null,
  meta_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_company_subscription_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_company_subscription_status_ck
    check (status in ('trial','active','past_due','paused','cancelled','expired'))
);

create index if not exists AMS_company_subscription_company_idx
  on AMS_company_subscription (AMS_company_id);

create index if not exists AMS_company_subscription_status_idx
  on AMS_company_subscription (status);

create trigger AMS_company_subscription_set_updated_at_trg
before update on AMS_company_subscription
for each row execute function AMS_fn_set_updated_at();

alter table AMS_company_subscription enable row level security;

-- -----------------------------------------------------------------------------
-- Custom authentication / authorization
-- -----------------------------------------------------------------------------

create table if not exists AMS_user (
  id uuid primary key,
  display_name text not null,
  email text null,
  mobile text null,
  username text null,
  password_hash text not null,
  password_algo text not null default 'argon2id',
  is_active boolean not null default true,
  is_platform_super_admin boolean not null default false,
  failed_login_count int not null default 0,
  locked_until timestamptz null,
  last_login_at timestamptz null,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_user_email_ck check (email is null or position('@' in email) > 1),
  constraint AMS_user_failed_login_count_ck check (failed_login_count >= 0)
);

-- Uniqueness is platform-wide; partial uniques allow nulls.
create unique index if not exists AMS_user_email_uk
  on AMS_user (lower(email))
  where email is not null;

create unique index if not exists AMS_user_mobile_uk
  on AMS_user (mobile)
  where mobile is not null;

create unique index if not exists AMS_user_username_uk
  on AMS_user (lower(username))
  where username is not null;

create index if not exists AMS_user_is_active_idx
  on AMS_user (is_active);

create trigger AMS_user_set_updated_at_trg
before update on AMS_user
for each row execute function AMS_fn_set_updated_at();

alter table AMS_user enable row level security;

create table if not exists AMS_user_company_map (
  id uuid primary key,
  AMS_user_id uuid not null,
  AMS_company_id uuid not null,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_user_company_map_user_fk
    foreign key (AMS_user_id) references AMS_user(id) on delete cascade,
  constraint AMS_user_company_map_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade
);

alter table AMS_user_company_map
  add constraint AMS_user_company_map_user_company_uk unique (AMS_user_id, AMS_company_id);

create index if not exists AMS_user_company_map_company_idx
  on AMS_user_company_map (AMS_company_id, is_active);

create index if not exists AMS_user_company_map_user_idx
  on AMS_user_company_map (AMS_user_id, is_active);

create trigger AMS_user_company_map_set_updated_at_trg
before update on AMS_user_company_map
for each row execute function AMS_fn_set_updated_at();

alter table AMS_user_company_map enable row level security;

create table if not exists AMS_user_session (
  id uuid primary key,
  AMS_user_id uuid not null,
  AMS_company_id uuid null,
  access_token_hash text not null,
  refresh_token_hash text not null,
  issued_at timestamptz not null default AMS_fn_now_utc(),
  access_expires_at timestamptz not null,
  refresh_expires_at timestamptz not null,
  revoked_at timestamptz null,
  client_type text not null default 'web',
  device_id text null,
  ip_address inet null,
  user_agent text null,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_user_session_user_fk
    foreign key (AMS_user_id) references AMS_user(id) on delete cascade,
  constraint AMS_user_session_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete set null,
  constraint AMS_user_session_client_type_ck
    check (client_type in ('web','mobile','kiosk','api')),
  constraint AMS_user_session_expiry_ck
    check (access_expires_at <= refresh_expires_at)
);

create index if not exists AMS_user_session_user_idx
  on AMS_user_session (AMS_user_id, revoked_at);

create index if not exists AMS_user_session_company_idx
  on AMS_user_session (AMS_company_id);

create unique index if not exists AMS_user_session_access_token_uk
  on AMS_user_session (access_token_hash);

create unique index if not exists AMS_user_session_refresh_token_uk
  on AMS_user_session (refresh_token_hash);

create trigger AMS_user_session_set_updated_at_trg
before update on AMS_user_session
for each row execute function AMS_fn_set_updated_at();

alter table AMS_user_session enable row level security;

create table if not exists AMS_user_login_audit (
  id uuid primary key,
  AMS_user_id uuid null,
  identifier text not null,
  success boolean not null,
  failure_reason text null,
  ip_address inet null,
  user_agent text null,
  occurred_at timestamptz not null default AMS_fn_now_utc(),
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_user_login_audit_user_fk
    foreign key (AMS_user_id) references AMS_user(id) on delete set null
);

create index if not exists AMS_user_login_audit_user_idx
  on AMS_user_login_audit (AMS_user_id, occurred_at desc);

create index if not exists AMS_user_login_audit_identifier_idx
  on AMS_user_login_audit (identifier, occurred_at desc);

create trigger AMS_user_login_audit_set_updated_at_trg
before update on AMS_user_login_audit
for each row execute function AMS_fn_set_updated_at();

alter table AMS_user_login_audit enable row level security;

-- -----------------------------------------------------------------------------
-- RBAC
-- -----------------------------------------------------------------------------

create table if not exists AMS_role (
  id uuid primary key,
  AMS_company_id uuid null,
  code text not null,
  name text not null,
  description text null,
  is_platform_role boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_role_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade
);

create unique index if not exists AMS_role_platform_code_uk
  on AMS_role (code)
  where AMS_company_id is null;

create unique index if not exists AMS_role_company_code_uk
  on AMS_role (AMS_company_id, code)
  where AMS_company_id is not null;

create index if not exists AMS_role_company_idx
  on AMS_role (AMS_company_id, is_active);

create trigger AMS_role_set_updated_at_trg
before update on AMS_role
for each row execute function AMS_fn_set_updated_at();

alter table AMS_role enable row level security;

create table if not exists AMS_permission (
  id uuid primary key,
  code text not null,
  name text not null,
  description text null,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null
);

alter table AMS_permission
  add constraint AMS_permission_code_uk unique (code);

create trigger AMS_permission_set_updated_at_trg
before update on AMS_permission
for each row execute function AMS_fn_set_updated_at();

alter table AMS_permission enable row level security;

create table if not exists AMS_user_role_map (
  id uuid primary key,
  AMS_user_id uuid not null,
  AMS_role_id uuid not null,
  AMS_company_id uuid null,
  is_active boolean not null default true,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_user_role_map_user_fk
    foreign key (AMS_user_id) references AMS_user(id) on delete cascade,
  constraint AMS_user_role_map_role_fk
    foreign key (AMS_role_id) references AMS_role(id) on delete cascade,
  constraint AMS_user_role_map_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade
);

alter table AMS_user_role_map
  add constraint AMS_user_role_map_uk unique (AMS_user_id, AMS_role_id, AMS_company_id);

create index if not exists AMS_user_role_map_user_idx
  on AMS_user_role_map (AMS_user_id, is_active);

create index if not exists AMS_user_role_map_company_idx
  on AMS_user_role_map (AMS_company_id, is_active);

create trigger AMS_user_role_map_set_updated_at_trg
before update on AMS_user_role_map
for each row execute function AMS_fn_set_updated_at();

alter table AMS_user_role_map enable row level security;

-- Optional: role->permission map (not in mandatory list but required for real RBAC)
create table if not exists AMS_role_permission_map (
  id uuid primary key,
  AMS_role_id uuid not null,
  AMS_permission_id uuid not null,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_role_permission_map_role_fk
    foreign key (AMS_role_id) references AMS_role(id) on delete cascade,
  constraint AMS_role_permission_map_permission_fk
    foreign key (AMS_permission_id) references AMS_permission(id) on delete cascade
);

alter table AMS_role_permission_map
  add constraint AMS_role_permission_map_uk unique (AMS_role_id, AMS_permission_id);

create index if not exists AMS_role_permission_map_role_idx
  on AMS_role_permission_map (AMS_role_id);

create trigger AMS_role_permission_map_set_updated_at_trg
before update on AMS_role_permission_map
for each row execute function AMS_fn_set_updated_at();

alter table AMS_role_permission_map enable row level security;

-- -----------------------------------------------------------------------------
-- Audit log (platform wide)
-- -----------------------------------------------------------------------------

create table if not exists AMS_audit_log (
  id uuid primary key,
  AMS_company_id uuid null,
  actor_user_id uuid null,
  action_code text not null,
  entity_type text null,
  entity_id uuid null,
  details_json jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default AMS_fn_now_utc(),
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_audit_log_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete set null,
  constraint AMS_audit_log_actor_fk
    foreign key (actor_user_id) references AMS_user(id) on delete set null
);

create index if not exists AMS_audit_log_company_time_idx
  on AMS_audit_log (AMS_company_id, occurred_at desc);

create index if not exists AMS_audit_log_action_idx
  on AMS_audit_log (action_code, occurred_at desc);

create trigger AMS_audit_log_set_updated_at_trg
before update on AMS_audit_log
for each row execute function AMS_fn_set_updated_at();

alter table AMS_audit_log enable row level security;

commit;

