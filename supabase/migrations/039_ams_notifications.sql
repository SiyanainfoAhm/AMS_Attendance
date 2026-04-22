-- Notifications: push tokens + in-app inbox

begin;

create table if not exists AMS_push_token (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_user_id uuid not null,
  device_id text null,
  platform text null,
  push_token text not null,
  is_enabled boolean not null default true,
  last_seen_at timestamptz not null default AMS_fn_now_utc(),
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  constraint AMS_push_token_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_push_token_user_fk
    foreign key (AMS_user_id) references AMS_user(id) on delete cascade,
  constraint AMS_push_token_platform_ck check (platform in ('android','ios','web') or platform is null)
);

create unique index if not exists AMS_push_token_user_token_uk
  on AMS_push_token (AMS_user_id, push_token);

create index if not exists AMS_push_token_company_enabled_idx
  on AMS_push_token (AMS_company_id, is_enabled, updated_at desc);

drop trigger if exists AMS_push_token_set_updated_at_trg on AMS_push_token;
create trigger AMS_push_token_set_updated_at_trg
before update on AMS_push_token
for each row execute function AMS_fn_set_updated_at();

alter table AMS_push_token enable row level security;

create table if not exists AMS_notification (
  id uuid primary key,
  AMS_company_id uuid not null,
  AMS_user_id uuid not null,
  notif_type text not null default 'generic',
  title text not null,
  body text null,
  payload_json jsonb not null default '{}'::jsonb,
  status text not null default 'queued',
  channel text not null default 'push',
  priority text not null default 'normal',
  sent_at timestamptz null,
  read_at timestamptz null,
  created_at timestamptz not null default AMS_fn_now_utc(),
  updated_at timestamptz not null default AMS_fn_now_utc(),
  created_by uuid null,
  updated_by uuid null,
  constraint AMS_notification_company_fk
    foreign key (AMS_company_id) references AMS_company(id) on delete cascade,
  constraint AMS_notification_user_fk
    foreign key (AMS_user_id) references AMS_user(id) on delete cascade,
  constraint AMS_notification_status_ck check (status in ('queued','sent','failed','read')),
  constraint AMS_notification_channel_ck check (channel in ('push','inbox')),
  constraint AMS_notification_priority_ck check (priority in ('low','normal','high'))
);

create index if not exists AMS_notification_company_user_time_idx
  on AMS_notification (AMS_company_id, AMS_user_id, created_at desc);

create index if not exists AMS_notification_status_time_idx
  on AMS_notification (status, created_at desc);

drop trigger if exists AMS_notification_set_updated_at_trg on AMS_notification;
create trigger AMS_notification_set_updated_at_trg
before update on AMS_notification
for each row execute function AMS_fn_set_updated_at();

alter table AMS_notification enable row level security;

commit;

