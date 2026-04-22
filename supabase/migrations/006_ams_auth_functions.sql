-- Phase 3 / Migration 006: Custom auth functions (email + password)
-- Implementation notes:
-- - Uses pgcrypto `crypt()` with bcrypt (`gen_salt('bf')`)
-- - Stores only token hashes in DB (sha256 via `digest`)
-- - Designed to be called via Edge Functions using service role

begin;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------

create or replace function AMS_fn_hash_token(p_token text)
returns text
language sql
stable
as $$
  select encode(digest(p_token, 'sha256'), 'hex');
$$;

create or replace function AMS_fn_new_token(p_bytes int default 32)
returns text
language sql
volatile
as $$
  -- URL-safe base64 without padding
  select translate(rtrim(encode(gen_random_bytes(p_bytes), 'base64'), '='), '+/', '-_');
$$;

create or replace function AMS_fn_password_hash_bcrypt(p_password text)
returns text
language sql
volatile
as $$
  select crypt(p_password, gen_salt('bf', 12));
$$;

create or replace function AMS_fn_password_verify_bcrypt(p_password text, p_hash text)
returns boolean
language sql
stable
as $$
  select crypt(p_password, p_hash) = p_hash;
$$;

create or replace function AMS_fn_get_user_companies(p_user_id uuid)
returns table (
  company_id uuid,
  company_code text,
  company_name text
)
language sql
stable
as $$
  select
    c.id as company_id,
    c.code as company_code,
    c.name as company_name
  from AMS_user_company_map ucm
  join AMS_company c on c.id = ucm.AMS_company_id
  where ucm.AMS_user_id = p_user_id
    and ucm.is_active = true
    and c.is_active = true
  order by c.name;
$$;

create or replace function AMS_fn_validate_user_company_access(
  p_user_id uuid,
  p_company_id uuid
)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from AMS_user_company_map ucm
    join AMS_company c on c.id = ucm.AMS_company_id
    where ucm.AMS_user_id = p_user_id
      and ucm.AMS_company_id = p_company_id
      and ucm.is_active = true
      and c.is_active = true
  );
$$;

create or replace function AMS_fn_validate_user_session(
  p_access_token text
)
returns table (
  session_id uuid,
  user_id uuid,
  company_id uuid,
  access_expires_at timestamptz,
  revoked_at timestamptz
)
language sql
stable
as $$
  select
    s.id as session_id,
    s.AMS_user_id as user_id,
    s.AMS_company_id as company_id,
    s.access_expires_at,
    s.revoked_at
  from AMS_user_session s
  where s.access_token_hash = AMS_fn_hash_token(p_access_token)
    and s.revoked_at is null
    and s.access_expires_at > AMS_fn_now_utc();
$$;

-- -----------------------------------------------------------------------------
-- Login / logout / refresh
-- -----------------------------------------------------------------------------

create or replace function AMS_sp_user_login(
  p_email text,
  p_password text,
  p_client_type text default 'web',
  p_device_id text default null,
  p_ip_address inet default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_user AMS_user%rowtype;
  v_now timestamptz := AMS_fn_now_utc();
  v_access_token text;
  v_refresh_token text;
  v_session_id uuid := gen_random_uuid();
  v_access_expires_at timestamptz := v_now + interval '15 minutes';
  v_refresh_expires_at timestamptz := v_now + interval '30 days';
  v_failure_reason text;
  v_companies jsonb;
begin
  if p_email is null or length(trim(p_email)) = 0 then
    raise exception 'email_required';
  end if;
  if p_password is null or length(p_password) = 0 then
    raise exception 'password_required';
  end if;

  select * into v_user
  from AMS_user u
  where lower(u.email) = lower(trim(p_email))
  limit 1;

  if not found then
    v_failure_reason := 'user_not_found';
    insert into AMS_user_login_audit (id, AMS_user_id, identifier, success, failure_reason, ip_address, user_agent, occurred_at)
    values (gen_random_uuid(), null, p_email, false, v_failure_reason, p_ip_address, p_user_agent, v_now);
    raise exception 'invalid_credentials';
  end if;

  if v_user.is_active = false then
    v_failure_reason := 'user_inactive';
    insert into AMS_user_login_audit (id, AMS_user_id, identifier, success, failure_reason, ip_address, user_agent, occurred_at)
    values (gen_random_uuid(), v_user.id, p_email, false, v_failure_reason, p_ip_address, p_user_agent, v_now);
    raise exception 'user_inactive';
  end if;

  if v_user.locked_until is not null and v_user.locked_until > v_now then
    v_failure_reason := 'locked';
    insert into AMS_user_login_audit (id, AMS_user_id, identifier, success, failure_reason, ip_address, user_agent, occurred_at)
    values (gen_random_uuid(), v_user.id, p_email, false, v_failure_reason, p_ip_address, p_user_agent, v_now);
    raise exception 'account_locked';
  end if;

  if not AMS_fn_password_verify_bcrypt(p_password, v_user.password_hash) then
    update AMS_user
      set failed_login_count = failed_login_count + 1,
          locked_until = case when failed_login_count + 1 >= 5 then v_now + interval '15 minutes' else locked_until end,
          updated_at = v_now
    where id = v_user.id;

    v_failure_reason := 'invalid_password';
    insert into AMS_user_login_audit (id, AMS_user_id, identifier, success, failure_reason, ip_address, user_agent, occurred_at)
    values (gen_random_uuid(), v_user.id, p_email, false, v_failure_reason, p_ip_address, p_user_agent, v_now);
    raise exception 'invalid_credentials';
  end if;

  -- success: reset counters
  update AMS_user
    set failed_login_count = 0,
        locked_until = null,
        last_login_at = v_now,
        updated_at = v_now
  where id = v_user.id;

  v_access_token := AMS_fn_new_token(32);
  v_refresh_token := AMS_fn_new_token(48);

  insert into AMS_user_session (
    id,
    AMS_user_id,
    AMS_company_id,
    access_token_hash,
    refresh_token_hash,
    issued_at,
    access_expires_at,
    refresh_expires_at,
    client_type,
    device_id,
    ip_address,
    user_agent
  ) values (
    v_session_id,
    v_user.id,
    null,
    AMS_fn_hash_token(v_access_token),
    AMS_fn_hash_token(v_refresh_token),
    v_now,
    v_access_expires_at,
    v_refresh_expires_at,
    p_client_type,
    p_device_id,
    p_ip_address,
    p_user_agent
  );

  insert into AMS_user_login_audit (id, AMS_user_id, identifier, success, failure_reason, ip_address, user_agent, occurred_at)
  values (gen_random_uuid(), v_user.id, p_email, true, null, p_ip_address, p_user_agent, v_now);

  select coalesce(jsonb_agg(jsonb_build_object('id', t.company_id, 'code', t.company_code, 'name', t.company_name)), '[]'::jsonb)
  into v_companies
  from AMS_fn_get_user_companies(v_user.id) t;

  return jsonb_build_object(
    'user', jsonb_build_object('id', v_user.id, 'display_name', v_user.display_name, 'email', v_user.email),
    'companies', v_companies,
    'session', jsonb_build_object(
      'session_id', v_session_id,
      'access_token', v_access_token,
      'refresh_token', v_refresh_token,
      'access_expires_at', v_access_expires_at,
      'refresh_expires_at', v_refresh_expires_at
    )
  );
end;
$$;

create or replace function AMS_sp_user_logout(
  p_access_token text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_hash text := AMS_fn_hash_token(p_access_token);
  v_updated int;
begin
  update AMS_user_session
    set revoked_at = v_now,
        updated_at = v_now
  where access_token_hash = v_hash
    and revoked_at is null;

  get diagnostics v_updated = row_count;

  return jsonb_build_object('revoked', v_updated > 0);
end;
$$;

create or replace function AMS_sp_refresh_session(
  p_refresh_token text,
  p_client_type text default 'web',
  p_device_id text default null,
  p_ip_address inet default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_old AMS_user_session%rowtype;
  v_new_access text;
  v_new_refresh text;
  v_access_expires_at timestamptz := v_now + interval '15 minutes';
  v_refresh_expires_at timestamptz := v_now + interval '30 days';
  v_new_session_id uuid := gen_random_uuid();
begin
  if p_refresh_token is null or length(p_refresh_token) = 0 then
    raise exception 'refresh_token_required';
  end if;

  select * into v_old
  from AMS_user_session s
  where s.refresh_token_hash = AMS_fn_hash_token(p_refresh_token)
    and s.revoked_at is null
    and s.refresh_expires_at > v_now
  limit 1;

  if not found then
    raise exception 'invalid_refresh_token';
  end if;

  -- rotate: revoke old session, issue new tokens
  update AMS_user_session
    set revoked_at = v_now,
        updated_at = v_now
  where id = v_old.id;

  v_new_access := AMS_fn_new_token(32);
  v_new_refresh := AMS_fn_new_token(48);

  insert into AMS_user_session (
    id,
    AMS_user_id,
    AMS_company_id,
    access_token_hash,
    refresh_token_hash,
    issued_at,
    access_expires_at,
    refresh_expires_at,
    client_type,
    device_id,
    ip_address,
    user_agent
  ) values (
    v_new_session_id,
    v_old.AMS_user_id,
    v_old.AMS_company_id,
    AMS_fn_hash_token(v_new_access),
    AMS_fn_hash_token(v_new_refresh),
    v_now,
    v_access_expires_at,
    v_refresh_expires_at,
    p_client_type,
    coalesce(p_device_id, v_old.device_id),
    coalesce(p_ip_address, v_old.ip_address),
    coalesce(p_user_agent, v_old.user_agent)
  );

  return jsonb_build_object(
    'session', jsonb_build_object(
      'session_id', v_new_session_id,
      'access_token', v_new_access,
      'refresh_token', v_new_refresh,
      'access_expires_at', v_access_expires_at,
      'refresh_expires_at', v_refresh_expires_at
    )
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Password management
-- -----------------------------------------------------------------------------

create or replace function AMS_sp_change_password(
  p_access_token text,
  p_old_password text,
  p_new_password text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_sess record;
  v_user AMS_user%rowtype;
begin
  select * into v_sess from AMS_fn_validate_user_session(p_access_token) limit 1;
  if not found then
    raise exception 'invalid_session';
  end if;

  select * into v_user from AMS_user where id = v_sess.user_id limit 1;
  if not found then
    raise exception 'user_not_found';
  end if;

  if not AMS_fn_password_verify_bcrypt(p_old_password, v_user.password_hash) then
    raise exception 'invalid_old_password';
  end if;

  update AMS_user
    set password_hash = AMS_fn_password_hash_bcrypt(p_new_password),
        password_algo = 'bcrypt',
        updated_at = v_now
  where id = v_user.id;

  -- revoke all sessions for safety
  update AMS_user_session
    set revoked_at = v_now,
        updated_at = v_now
  where AMS_user_id = v_user.id
    and revoked_at is null;

  return jsonb_build_object('changed', true);
end;
$$;

commit;

