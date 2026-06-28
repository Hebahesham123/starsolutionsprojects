-- ============================================================================
-- Star Solutions — create the admin users (Ahmed, Hams, Mera, Martha)
-- ----------------------------------------------------------------------------
-- Run order in the Supabase SQL editor:
--   1. supabase/schema.sql   (tables, triggers, RLS)   <-- run first
--   2. supabase/admins.sql   (this file)               <-- creates the admins
--   3. supabase/seed.sql     (optional demo data)
--
-- This creates real, login-ready accounts in Supabase Auth and marks every
-- one of them as role = 'admin' in public.users.
--
-- >>> BEFORE RUNNING: edit the emails and passwords in the VALUES list below.
--     The defaults below are placeholders — change them to real addresses and
--     strong passwords. Each user should change their password after first login.
-- ============================================================================

-- pgcrypto is needed for crypt()/gen_salt() (schema.sql already enables it).
create extension if not exists "pgcrypto";

do $admins$
declare
  u   record;
  uid uuid;
begin
  for u in (
    select * from (values
      -- email                       full name   password
      ('ahmed@starsolutions.com',     'Ahmed',  'ChangeMe!2026'),
      ('hams@starsolutions.com',      'Hams',   'ChangeMe!2026'),
      ('mera@starsolutions.com',      'Mera',   'ChangeMe!2026'),
      ('martha@starsolutions.com',    'Martha', 'ChangeMe!2026'),
      ('hebahesham102@gmail.com',     'Heba',   'ChangeMe!2026')
    ) as t(email, full_name, password)
  ) loop

    -- Reuse the account if it already exists (makes this script re-runnable).
    select id into uid from auth.users where email = lower(u.email);

    if uid is null then
      uid := gen_random_uuid();

      -- 1) Auth account (email confirmed so they can log in immediately).
      --    NOTE: the token columns MUST be '' (empty string), never NULL —
      --    GoTrue scans them into Go strings on login and a NULL there throws
      --    "Database error querying schema".
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, created_at, updated_at,
        raw_app_meta_data, raw_user_meta_data, is_super_admin,
        confirmation_token, recovery_token, email_change, email_change_token_new
      ) values (
        '00000000-0000-0000-0000-000000000000',
        uid, 'authenticated', 'authenticated',
        lower(u.email),
        crypt(u.password, gen_salt('bf')),
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('full_name', u.full_name),
        false,
        '', '', '', ''
      );

      -- 2) Email identity (required by Supabase Auth for email/password login).
      insert into auth.identities (
        id, user_id, provider_id, identity_data,
        provider, last_sign_in_at, created_at, updated_at
      ) values (
        gen_random_uuid(), uid, uid::text,
        jsonb_build_object('sub', uid::text, 'email', lower(u.email), 'email_verified', true),
        'email', now(), now(), now()
      );
    end if;

    -- 3) Profile row — force role = admin (the on-signup trigger may have
    --    created this row already and defaulted it to team_member).
    insert into public.users (id, email, full_name, role)
    values (uid, lower(u.email), u.full_name, 'admin')
    on conflict (id) do update
      set role      = 'admin',
          full_name = excluded.full_name,
          email     = excluded.email;

  end loop;
end $admins$;

-- ----------------------------------------------------------------------------
-- Repair any auth.users rows whose token columns are NULL (e.g. created by an
-- earlier run of this script before the '' fix). NULL here makes GoTrue fail
-- login with "Database error querying schema". Safe to run every time.
-- ----------------------------------------------------------------------------
update auth.users set
  confirmation_token     = coalesce(confirmation_token, ''),
  recovery_token         = coalesce(recovery_token, ''),
  email_change           = coalesce(email_change, ''),
  email_change_token_new = coalesce(email_change_token_new, '')
where confirmation_token is null
   or recovery_token is null
   or email_change is null
   or email_change_token_new is null;

-- ----------------------------------------------------------------------------
-- Verify
-- ----------------------------------------------------------------------------
select full_name, email, role, created_at
from public.users
where role = 'admin'
order by created_at;

-- ============================================================================
-- ALTERNATIVE (if the block above errors on your Supabase version):
-- Create the four users from the Dashboard instead
--   Authentication -> Users -> "Add user" -> Auto Confirm User
-- then promote them to admin by running ONLY this:
--
-- update public.users
--    set role = 'admin'
--  where email in (
--    'ahmed@starsolutions.com',
--    'hams@starsolutions.com',
--    'mera@starsolutions.com',
--    'martha@starsolutions.com',
--    'hebahesham102@gmail.com'
--  );
-- ============================================================================
