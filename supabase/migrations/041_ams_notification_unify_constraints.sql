-- Unify AMS_notification check constraints across legacy (004) and app (039+) shapes.
-- Some environments created AMS_notification in 004 first; later code expects statuses like
-- `read` and channels like `inbox`, which the legacy checks reject.

begin;

do $$
declare
  r record;
begin
  if to_regclass('public.ams_notification') is null then
    return;
  end if;

  for r in
    select c.conname
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'ams_notification'
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) ilike '%channel%'
  loop
    execute format('alter table AMS_notification drop constraint if exists %I', r.conname);
  end loop;

  for r in
    select c.conname
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'ams_notification'
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) ilike '%status%'
  loop
    execute format('alter table AMS_notification drop constraint if exists %I', r.conname);
  end loop;

  for r in
    select c.conname
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'ams_notification'
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) ilike '%priority%'
  loop
    execute format('alter table AMS_notification drop constraint if exists %I', r.conname);
  end loop;
end $$;

do $$
begin
  if to_regclass('public.ams_notification') is null then
    return;
  end if;

  alter table AMS_notification
    add constraint AMS_notification_channel_ck
      check (channel in ('push','email','sms','in_app','inbox'));

  alter table AMS_notification
    add constraint AMS_notification_status_ck
      check (status in ('draft','queued','sent','failed','read'));

  alter table AMS_notification
    add constraint AMS_notification_priority_ck
      check (priority in ('low','normal','high'));
exception
  when duplicate_object then
    null;
end $$;

commit;
