-- Hotfix: make pgcrypto calls work regardless of search_path
-- Supabase often installs pgcrypto functions under the `extensions` schema.

begin;

-- Ensure extension exists (idempotent).
create extension if not exists pgcrypto;

-- Recreate helpers with schema-qualified pgcrypto calls.
create or replace function AMS_fn_hash_token(p_token text)
returns text
language sql
stable
as $$
  select encode(extensions.digest(p_token, 'sha256'), 'hex');
$$;

create or replace function AMS_fn_new_token(p_bytes int default 32)
returns text
language sql
volatile
as $$
  -- URL-safe base64 without padding
  select translate(rtrim(encode(extensions.gen_random_bytes(p_bytes), 'base64'), '='), '+/', '-_');
$$;

create or replace function AMS_fn_password_hash_bcrypt(p_password text)
returns text
language sql
volatile
as $$
  select extensions.crypt(p_password, extensions.gen_salt('bf', 12));
$$;

create or replace function AMS_fn_password_verify_bcrypt(p_password text, p_hash text)
returns boolean
language sql
stable
as $$
  select extensions.crypt(p_password, p_hash) = p_hash;
$$;

-- Also update password reset procedures to include extensions in search_path
-- to avoid issues if SQL inlining occurs.
create or replace function AMS_sp_request_password_reset(
  p_email text,
  p_ip_address inet default null,
  p_user_agent text default null,
  p_include_token_in_response boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user AMS_user%rowtype;
  v_now timestamptz := AMS_fn_now_utc();
  v_token text;
  v_expires timestamptz := v_now + interval '1 hour';
begin
  if p_email is null or length(trim(p_email)) = 0 then
    return jsonb_build_object('requested', true);
  end if;

  select * into v_user
  from AMS_user u
  where lower(u.email) = lower(trim(p_email))
  limit 1;

  if not found then
    return jsonb_build_object('requested', true);
  end if;

  if v_user.is_active = false then
    return jsonb_build_object('requested', true);
  end if;

  update AMS_user_password_reset
  set used_at = v_now
  where AMS_user_id = v_user.id
    and used_at is null
    and expires_at > v_now;

  v_token := AMS_fn_new_token(48);

  insert into AMS_user_password_reset (
    id,
    AMS_user_id,
    token_hash,
    expires_at,
    used_at,
    created_at,
    ip_address,
    user_agent
  ) values (
    gen_random_uuid(),
    v_user.id,
    AMS_fn_hash_token(v_token),
    v_expires,
    null,
    v_now,
    p_ip_address,
    p_user_agent
  );

  if p_include_token_in_response then
    return jsonb_build_object('requested', true, 'reset_token', v_token);
  end if;

  return jsonb_build_object('requested', true);
end;
$$;

create or replace function AMS_sp_reset_password(
  p_reset_token text,
  p_new_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_now timestamptz := AMS_fn_now_utc();
  v_row AMS_user_password_reset%rowtype;
  v_user AMS_user%rowtype;
begin
  if p_reset_token is null or length(trim(p_reset_token)) = 0 then
    raise exception 'reset_token_required';
  end if;
  if p_new_password is null or length(p_new_password) < 8 then
    raise exception 'password_too_short';
  end if;

  select * into v_row
  from AMS_user_password_reset r
  where r.token_hash = AMS_fn_hash_token(p_reset_token)
    and r.used_at is null
    and r.expires_at > v_now
  limit 1;

  if not found then
    raise exception 'invalid_or_expired_reset_token';
  end if;

  select * into v_user from AMS_user where id = v_row.AMS_user_id limit 1;
  if not found then
    raise exception 'user_not_found';
  end if;

  update AMS_user
  set password_hash = AMS_fn_password_hash_bcrypt(p_new_password),
      password_algo = 'bcrypt',
      failed_login_count = 0,
      locked_until = null,
      updated_at = v_now
  where id = v_user.id;

  update AMS_user_session
  set revoked_at = v_now,
      updated_at = v_now
  where AMS_user_id = v_user.id
    and revoked_at is null;

  update AMS_user_password_reset
  set used_at = v_now
  where id = v_row.id;

  return jsonb_build_object('reset', true);
end;
$$;

commit;

