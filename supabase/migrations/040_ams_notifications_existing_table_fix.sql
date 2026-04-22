-- Fix for environments where ams_push_token / ams_notification already exist
-- but are missing expected columns (e.g. ams_user_id).

begin;

-- AMS_push_token: add missing columns (non-destructive)
alter table if exists AMS_push_token
  add column if not exists AMS_company_id uuid,
  add column if not exists AMS_user_id uuid,
  add column if not exists device_id text,
  add column if not exists platform text,
  add column if not exists push_token text,
  add column if not exists is_enabled boolean,
  add column if not exists last_seen_at timestamptz,
  add column if not exists created_at timestamptz,
  add column if not exists updated_at timestamptz;

-- backfill defaults where possible (only if table exists)
do $$
begin
  if to_regclass('public.ams_push_token') is not null then
    execute $q$
      update AMS_push_token
      set
        is_enabled = coalesce(is_enabled, true),
        last_seen_at = coalesce(last_seen_at, AMS_fn_now_utc()),
        created_at = coalesce(created_at, AMS_fn_now_utc()),
        updated_at = coalesce(updated_at, AMS_fn_now_utc())
      where
        is_enabled is null
        or last_seen_at is null
        or created_at is null
        or updated_at is null
    $q$;
  end if;
end $$;

-- enforce not-null where safe (only if column exists and table empty checks are avoided)
-- (we keep these nullable to avoid breaking legacy rows that have no mapping yet)

do $$
begin
  -- indexes
  execute 'create unique index if not exists AMS_push_token_user_token_uk on AMS_push_token (AMS_user_id, push_token)';
  execute 'create index if not exists AMS_push_token_company_enabled_idx on AMS_push_token (AMS_company_id, is_enabled, updated_at desc)';
exception when others then
  -- ignore if table doesn't exist or columns still missing
  null;
end $$;

do $$
begin
  -- trigger (idempotent)
  execute 'drop trigger if exists AMS_push_token_set_updated_at_trg on AMS_push_token';
  execute 'create trigger AMS_push_token_set_updated_at_trg before update on AMS_push_token for each row execute function AMS_fn_set_updated_at()';
exception when others then
  null;
end $$;

alter table if exists AMS_push_token enable row level security;

-- AMS_notification: add missing columns (non-destructive)
alter table if exists AMS_notification
  add column if not exists AMS_company_id uuid,
  add column if not exists AMS_user_id uuid,
  add column if not exists notif_type text,
  add column if not exists title text,
  add column if not exists body text,
  add column if not exists payload_json jsonb,
  add column if not exists status text,
  add column if not exists channel text,
  add column if not exists priority text,
  add column if not exists sent_at timestamptz,
  add column if not exists read_at timestamptz,
  add column if not exists created_at timestamptz,
  add column if not exists updated_at timestamptz,
  add column if not exists created_by uuid,
  add column if not exists updated_by uuid;

do $$
begin
  if to_regclass('public.ams_notification') is not null then
    execute $q$
      update AMS_notification
      set
        notif_type = coalesce(notif_type, 'generic'),
        payload_json = coalesce(payload_json, '{}'::jsonb),
        status = coalesce(status, 'queued'),
        channel = coalesce(channel, 'push'),
        priority = coalesce(priority, 'normal'),
        created_at = coalesce(created_at, AMS_fn_now_utc()),
        updated_at = coalesce(updated_at, AMS_fn_now_utc())
      where
        notif_type is null
        or payload_json is null
        or status is null
        or channel is null
        or priority is null
        or created_at is null
        or updated_at is null
    $q$;
  end if;
end $$;

do $$
begin
  execute 'create index if not exists AMS_notification_company_user_time_idx on AMS_notification (AMS_company_id, AMS_user_id, created_at desc)';
  execute 'create index if not exists AMS_notification_status_time_idx on AMS_notification (status, created_at desc)';
exception when others then
  null;
end $$;

do $$
begin
  execute 'drop trigger if exists AMS_notification_set_updated_at_trg on AMS_notification';
  execute 'create trigger AMS_notification_set_updated_at_trg before update on AMS_notification for each row execute function AMS_fn_set_updated_at()';
exception when others then
  null;
end $$;

alter table if exists AMS_notification enable row level security;

commit;

