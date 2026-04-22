-- DANGER: Wipes ALL AMS_* data (keeps schema/migrations).
-- Use in Supabase SQL editor or psql. Recommended for DEV/DEMO only.

begin;

-- Revoke all sessions first to avoid any surprises
update AMS_user_session set revoked_at = AMS_fn_now_utc() where revoked_at is null;

do $$
declare
  r record;
begin
  -- Truncate all application tables (AMS_*) in public schema.
  -- We exclude any non-table objects automatically; this only affects base tables.
  for r in
    select format('%I.%I', schemaname, tablename) as fqtn
    from pg_catalog.pg_tables
    where schemaname = 'public'
      and tablename ilike 'ams\_%' escape '\'
  loop
    execute 'truncate table ' || r.fqtn || ' restart identity cascade';
  end loop;
end $$;

commit;

