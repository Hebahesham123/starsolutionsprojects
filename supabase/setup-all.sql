-- ###########################################################################
-- ###########################################################################
-- ##   Star Solutions — COMPLETE one-shot database setup                    ##
-- ##   Run this WHOLE file ONCE in the Supabase SQL editor (top -> bottom). ##
-- ###########################################################################
--
-- Starts with an EMPTY database — no sample projects or tasks.
--
-- What it does, in order:
--   1) Schema: tables, enums, triggers, RLS policies
--   2) Project Manager field + manual/auto end-date mode
--   3) Multi-department arrays on projects/tasks
--   4) Helper fn user_can_see_project() (needed by step 5)
--   5) Project comments + attachments (+ storage bucket & policies)
--   6) Admin users: Ahmed, Hams, Mera, Martha, Heba
--
-- >>> BEFORE RUNNING: in section 6 (ADMIN USERS) edit the emails + passwords.
--
-- Note: the banner comments inside each section still say "run once" from when
-- they were separate files — that's fine, just run this single file.
-- ###########################################################################


-- ===========================================================================
-- ===== 1/6  SCHEMA  ========================================================
-- ===========================================================================
-- ============================================================================
-- Project Tracker — Supabase Schema
-- Run in the Supabase SQL Editor (top to bottom) on a fresh project.
-- ============================================================================

-- Extensions
create extension if not exists "pgcrypto";

-- ----------------------------------------------------------------------------
-- Default grants (restore after `drop schema public cascade`)
-- Supabase applies these automatically on new projects, but a schema reset
-- removes them. Re-granting here makes schema.sql safely re-runnable.
-- ----------------------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
grant all on all functions in schema public to anon, authenticated, service_role;

alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on functions to anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- ENUMS
-- ----------------------------------------------------------------------------
do $enums$ begin
  if not exists (select 1 from pg_type where typname = 'user_role') then
    create type user_role as enum ('admin', 'project_manager', 'team_member');
  end if;
  if not exists (select 1 from pg_type where typname = 'project_status') then
    create type project_status as enum ('not_started', 'in_progress', 'on_going', 'completed', 'delayed');
  end if;
  if not exists (select 1 from pg_type where typname = 'task_status') then
    create type task_status as enum ('todo', 'in_progress', 'on_going', 'done', 'blocked');
  end if;
end $enums$;

-- Idempotent additions for existing databases (ADD VALUE cannot run inside the do-block above)
alter type project_status add value if not exists 'on_going';
alter type task_status add value if not exists 'on_going';

-- ----------------------------------------------------------------------------
-- USERS (profile table, 1-1 with auth.users)
-- ----------------------------------------------------------------------------
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  full_name text,
  mobile text,
  role user_role not null default 'team_member',
  avatar_url text,
  created_at timestamptz not null default now()
);

-- Auto-create profile on signup; first user becomes admin.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  insert into public.users (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    case when not exists (select 1 from public.users) then 'admin'::user_role else 'team_member'::user_role end
  );
  return new;
end;
$fn$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ----------------------------------------------------------------------------
-- PROJECTS
-- ----------------------------------------------------------------------------
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  sector text,
  owner_name text,
  owner_email text,
  owner_mobile text,
  start_date date not null default current_date,
  estimated_end_date date,
  actual_end_date date,
  status project_status not null default 'not_started',
  completion_rate numeric(5,2) not null default 0,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_projects_status on public.projects(status);
create index if not exists idx_projects_created_by on public.projects(created_by);

-- ----------------------------------------------------------------------------
-- TASKS
-- ----------------------------------------------------------------------------
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  title text not null,
  description text,
  assignee_id uuid references public.users(id) on delete set null,
  assignee_name text,
  assignee_email text,
  assignee_mobile text,
  status task_status not null default 'todo',
  completion_percentage integer not null default 0 check (completion_percentage between 0 and 100),
  start_date date,
  due_date date,
  task_code text,
  task_type text check (task_type is null or task_type in ('DEP', 'IND')),
  blocked_by text,
  order_index integer not null default 0,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_tasks_project on public.tasks(project_id);
create index if not exists idx_tasks_assignee on public.tasks(assignee_id);
create index if not exists idx_tasks_status on public.tasks(status);
create index if not exists idx_tasks_due_date on public.tasks(due_date);

-- ----------------------------------------------------------------------------
-- COMMENTS
-- ----------------------------------------------------------------------------
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  author_id uuid references public.users(id) on delete set null,
  parent_id uuid references public.comments(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_comments_task on public.comments(task_id);

-- ----------------------------------------------------------------------------
-- NOTIFICATIONS
-- ----------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  kind text not null,
  title text not null,
  body text,
  link text,
  read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_notifications_user on public.notifications(user_id, read, created_at desc);

-- ----------------------------------------------------------------------------
-- ACTIVITY LOG
-- ----------------------------------------------------------------------------
create table if not exists public.activity_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.users(id) on delete set null,
  entity_type text not null,
  entity_id uuid not null,
  action text not null,
  meta jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_activity_created on public.activity_log(created_at desc);

-- ----------------------------------------------------------------------------
-- TRIGGERS: updated_at + completion roll-up + status automation
-- ----------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $fn$
begin
  new.updated_at := now();
  return new;
end;
$fn$;

drop trigger if exists trg_projects_touch on public.projects;
create trigger trg_projects_touch before update on public.projects
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_tasks_touch on public.tasks;
create trigger trg_tasks_touch before update on public.tasks
  for each row execute function public.touch_updated_at();

-- Keep completion_percentage consistent with status
create or replace function public.sync_task_status_completion()
returns trigger
language plpgsql
as $fn$
begin
  if new.status = 'done' then
    new.completion_percentage := 100;
  end if;
  if new.completion_percentage = 100 and new.status <> 'done' and new.status <> 'blocked' then
    new.status := 'done';
  end if;
  if new.completion_percentage is null then
    new.completion_percentage := 0;
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_tasks_sync on public.tasks;
create trigger trg_tasks_sync before insert or update on public.tasks
  for each row execute function public.sync_task_status_completion();

-- Recalculate project completion_rate and status from its tasks.
-- Implemented as a single UPDATE with correlated subqueries (no DECLARE vars).
create or replace function public.recalc_project_progress(p_id uuid)
returns void
language plpgsql
as $fn$
begin
  update public.projects p set
    completion_rate = coalesce(
      (select round(avg(completion_percentage)::numeric, 2) from public.tasks where project_id = p_id),
      0
    ),
    status = (
      case
        -- Preserve manually-set 'on_going' unless all tasks are done
        when p.status = 'on_going'::project_status
         and not (
           (select count(*) from public.tasks where project_id = p_id) > 0
           and (select count(*) from public.tasks where project_id = p_id)
             = (select count(*) from public.tasks where project_id = p_id and status = 'done')
         )
          then 'on_going'::project_status
        when (select count(*) from public.tasks where project_id = p_id) = 0
          then 'not_started'::project_status
        when (select count(*) from public.tasks where project_id = p_id)
           = (select count(*) from public.tasks where project_id = p_id and status = 'done')
          then 'completed'::project_status
        when p.estimated_end_date is not null and p.estimated_end_date < current_date
          then 'delayed'::project_status
        else 'in_progress'::project_status
      end
    ),
    actual_end_date = (
      case
        when (select count(*) from public.tasks where project_id = p_id) > 0
         and (select count(*) from public.tasks where project_id = p_id)
           = (select count(*) from public.tasks where project_id = p_id and status = 'done')
          then current_date
        else null
      end
    )
  where p.id = p_id;
end;
$fn$;

create or replace function public.tasks_after_change()
returns trigger
language plpgsql
as $fn$
begin
  perform public.recalc_project_progress(coalesce(new.project_id, old.project_id));
  return coalesce(new, old);
end;
$fn$;

drop trigger if exists trg_tasks_recalc on public.tasks;
create trigger trg_tasks_recalc after insert or update or delete on public.tasks
  for each row execute function public.tasks_after_change();

-- Notification when a task is assigned
create or replace function public.notify_on_assignment()
returns trigger
language plpgsql
as $fn$
begin
  if new.assignee_id is not null and (tg_op = 'INSERT' or new.assignee_id is distinct from old.assignee_id) then
    insert into public.notifications(user_id, kind, title, body, link)
    values (
      new.assignee_id,
      'task_assigned',
      'You were assigned a task',
      new.title,
      '/projects/' || new.project_id::text
    );
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_tasks_notify on public.tasks;
create trigger trg_tasks_notify after insert or update of assignee_id on public.tasks
  for each row execute function public.notify_on_assignment();

-- Notification on new comment → notify task assignee (if different from author)
create or replace function public.notify_on_comment()
returns trigger
language plpgsql
as $fn$
begin
  insert into public.notifications(user_id, kind, title, body, link)
  select
    t.assignee_id,
    'new_comment',
    'New comment on your task',
    t.title,
    '/projects/' || t.project_id::text
  from public.tasks t
  where t.id = new.task_id
    and t.assignee_id is not null
    and t.assignee_id is distinct from new.author_id;
  return new;
end;
$fn$;

drop trigger if exists trg_comments_notify on public.comments;
create trigger trg_comments_notify after insert on public.comments
  for each row execute function public.notify_on_comment();

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table public.users enable row level security;
alter table public.projects enable row level security;
alter table public.tasks enable row level security;
alter table public.comments enable row level security;
alter table public.notifications enable row level security;
alter table public.activity_log enable row level security;

-- Helper: current user's role
create or replace function public.current_user_role()
returns user_role
language sql
stable
security definer
set search_path = public
as $fn$
  select role from public.users where id = auth.uid();
$fn$;

-- USERS
drop policy if exists "users_read" on public.users;
create policy "users_read" on public.users for select using (auth.uid() is not null);

drop policy if exists "users_update_self" on public.users;
create policy "users_update_self" on public.users for update
  using (id = auth.uid() or public.current_user_role() = 'admin')
  with check (id = auth.uid() or public.current_user_role() = 'admin');

drop policy if exists "users_admin_insert" on public.users;
create policy "users_admin_insert" on public.users for insert
  with check (public.current_user_role() = 'admin');

drop policy if exists "users_admin_delete" on public.users;
create policy "users_admin_delete" on public.users for delete
  using (public.current_user_role() = 'admin');

-- PROJECTS
drop policy if exists "projects_read" on public.projects;
create policy "projects_read" on public.projects for select using (auth.uid() is not null);

-- Any signed-in user can create/edit/delete any project.
drop policy if exists "projects_write"     on public.projects;
drop policy if exists "projects_write_all" on public.projects;
create policy "projects_write_all" on public.projects for all
  using (auth.uid() is not null)
  with check (auth.uid() is not null);

-- TASKS
drop policy if exists "tasks_read" on public.tasks;
create policy "tasks_read" on public.tasks for select using (auth.uid() is not null);

-- Any signed-in user can create/edit/delete any task.
drop policy if exists "tasks_write_managers"  on public.tasks;
drop policy if exists "tasks_update_assignee" on public.tasks;
drop policy if exists "tasks_write_all"       on public.tasks;
create policy "tasks_write_all" on public.tasks for all
  using (auth.uid() is not null)
  with check (auth.uid() is not null);

-- COMMENTS
drop policy if exists "comments_read" on public.comments;
create policy "comments_read" on public.comments for select using (auth.uid() is not null);

drop policy if exists "comments_insert" on public.comments;
create policy "comments_insert" on public.comments for insert with check (author_id = auth.uid());

-- Any signed-in user can edit or delete any comment.
drop policy if exists "comments_delete_own" on public.comments;
drop policy if exists "comments_delete_all" on public.comments;
create policy "comments_delete_all" on public.comments for delete
  using (auth.uid() is not null);

drop policy if exists "comments_update_all" on public.comments;
create policy "comments_update_all" on public.comments for update
  using (auth.uid() is not null)
  with check (auth.uid() is not null);

-- NOTIFICATIONS
drop policy if exists "notif_read_own" on public.notifications;
create policy "notif_read_own" on public.notifications for select using (user_id = auth.uid());

drop policy if exists "notif_update_own" on public.notifications;
create policy "notif_update_own" on public.notifications for update using (user_id = auth.uid());

drop policy if exists "notif_insert" on public.notifications;
create policy "notif_insert" on public.notifications for insert with check (true);

drop policy if exists "notif_delete_own" on public.notifications;
create policy "notif_delete_own" on public.notifications for delete using (user_id = auth.uid());

-- ACTIVITY LOG
drop policy if exists "activity_read" on public.activity_log;
create policy "activity_read" on public.activity_log for select using (auth.uid() is not null);

drop policy if exists "activity_insert" on public.activity_log;
create policy "activity_insert" on public.activity_log for insert with check (auth.uid() is not null);

-- ----------------------------------------------------------------------------
-- REALTIME — safe to re-run
-- ----------------------------------------------------------------------------
do $pub$ begin
  begin
    alter publication supabase_realtime add table public.projects;
  exception when duplicate_object then null; end;
  begin
    alter publication supabase_realtime add table public.tasks;
  exception when duplicate_object then null; end;
  begin
    alter publication supabase_realtime add table public.comments;
  exception when duplicate_object then null; end;
  begin
    alter publication supabase_realtime add table public.notifications;
  exception when duplicate_object then null; end;
  begin
    alter publication supabase_realtime add table public.activity_log;
  exception when duplicate_object then null; end;
end $pub$;

-- ----------------------------------------------------------------------------
-- Final grant pass — ensures tables/functions created above are accessible
-- (default privileges only apply to *future* objects, so re-grant explicitly)
-- ----------------------------------------------------------------------------
grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
grant all on all functions in schema public to anon, authenticated, service_role;


-- ===========================================================================
-- ===== 2/6  PROJECT MANAGER + END-DATE MODE  ===============================
-- ===========================================================================
-- ============================================================================
-- Migration: Project Manager field + manual/auto end-date mode
-- Safe to re-run. Paste the whole file into Supabase SQL Editor and Run.
-- ============================================================================

-- 1) New columns on projects
alter table public.projects
  add column if not exists project_manager text;

alter table public.projects
  add column if not exists end_date_mode text not null default 'auto'
  check (end_date_mode in ('auto', 'manual'));

-- 2) Update recalc trigger so it respects end_date_mode = 'manual'
--    and leaves both actual_end_date AND status alone when the admin wants
--    full manual control.
create or replace function public.recalc_project_progress(p_id uuid)
returns void
language plpgsql
as $fn$
declare
  mode text;
begin
  select end_date_mode into mode from public.projects where id = p_id;

  if mode = 'manual' then
    -- Only recompute completion_rate — leave status and actual_end_date alone
    update public.projects p set
      completion_rate = coalesce(
        (select round(avg(completion_percentage)::numeric, 2) from public.tasks where project_id = p_id),
        p.completion_rate
      )
    where p.id = p_id;
    return;
  end if;

  -- Auto mode — original behaviour
  update public.projects p set
    completion_rate = coalesce(
      (select round(avg(completion_percentage)::numeric, 2) from public.tasks where project_id = p_id),
      0
    ),
    status = (
      case
        when (select count(*) from public.tasks where project_id = p_id) = 0
          then 'not_started'::project_status
        when (select count(*) from public.tasks where project_id = p_id)
           = (select count(*) from public.tasks where project_id = p_id and status = 'done')
          then 'completed'::project_status
        when p.estimated_end_date is not null and p.estimated_end_date < current_date
          then 'delayed'::project_status
        else 'in_progress'::project_status
      end
    ),
    actual_end_date = (
      case
        when (select count(*) from public.tasks where project_id = p_id) > 0
         and (select count(*) from public.tasks where project_id = p_id)
           = (select count(*) from public.tasks where project_id = p_id and status = 'done')
          then current_date
        else null
      end
    )
  where p.id = p_id;
end;
$fn$;


-- ===========================================================================
-- ===== 3/6  MULTI-DEPARTMENT  ==============================================
-- ===========================================================================
-- ============================================================================
-- Multi-department on projects and tasks.
-- Run once in the Supabase SQL editor.
-- ============================================================================

alter table public.projects
  add column if not exists departments text[] not null default '{}';

alter table public.tasks
  add column if not exists departments text[] not null default '{}';

-- Backfill from the legacy `sector` column on projects.
update public.projects
   set departments = array[sector]
 where sector is not null
   and (departments is null or array_length(departments, 1) is null);

create index if not exists idx_projects_departments on public.projects using gin (departments);
create index if not exists idx_tasks_departments    on public.tasks    using gin (departments);


-- ===========================================================================
-- ===== 4/6  HELPER: user_can_see_project()  ================================
-- Required by the comment/attachment RLS policies in section 5.
-- It is missing from the original repo files, so we define it here.
-- Mirrors the base "projects_read" policy (any signed-in user may see
-- projects); per-user scoping is done client-side in useScopedData.ts.
-- Tighten the body later if you want server-side project scoping.
-- ===========================================================================
create or replace function public.user_can_see_project(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $ucsp$
  select auth.uid() is not null;
$ucsp$;

-- ===========================================================================
-- ===== 5/6  PROJECT COMMENTS + ATTACHMENTS  ================================
-- ===========================================================================
-- ============================================================================
-- Comments on projects + Attachments (files / images) on tasks and projects.
-- Run once in the Supabase SQL editor.
-- ============================================================================

-- 1) Allow comments to belong to either a task OR a project.
alter table public.comments
  alter column task_id drop not null;

alter table public.comments
  add column if not exists project_id uuid references public.projects(id) on delete cascade;

-- Exactly one parent must be set.
alter table public.comments
  drop constraint if exists comments_parent_check;
alter table public.comments
  add constraint comments_parent_check
  check ((task_id is null) <> (project_id is null));

create index if not exists idx_comments_project on public.comments(project_id);

-- Tighten read policy: a user can read a comment only if they can see its parent.
drop policy if exists "comments_read" on public.comments;
create policy "comments_read" on public.comments for select using (
  auth.uid() is not null
  and (
    (task_id    is not null and exists (select 1 from public.tasks t    where t.id = comments.task_id    and public.user_can_see_project(t.project_id)))
    or
    (project_id is not null and public.user_can_see_project(comments.project_id))
  )
);

-- 2) Attachments table.
create table if not exists public.attachments (
  id uuid primary key default gen_random_uuid(),
  task_id    uuid references public.tasks(id)    on delete cascade,
  project_id uuid references public.projects(id) on delete cascade,
  comment_id uuid references public.comments(id) on delete cascade,
  storage_path text not null,
  file_name    text not null,
  content_type text,
  size_bytes   bigint,
  uploaded_by  uuid references public.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  constraint attachments_parent_check
    check (
      (task_id is not null)::int
      + (project_id is not null)::int
      + (comment_id is not null)::int
      = 1
    )
);
create index if not exists idx_attachments_task    on public.attachments(task_id);
create index if not exists idx_attachments_project on public.attachments(project_id);
create index if not exists idx_attachments_comment on public.attachments(comment_id);

alter table public.attachments enable row level security;

-- Read: visible if the user can see the parent project.
drop policy if exists "attachments_read" on public.attachments;
create policy "attachments_read" on public.attachments for select using (
  (task_id    is not null and exists (select 1 from public.tasks t where t.id = attachments.task_id and public.user_can_see_project(t.project_id)))
  or
  (project_id is not null and public.user_can_see_project(attachments.project_id))
  or
  (comment_id is not null and exists (
    select 1 from public.comments c
    where c.id = attachments.comment_id
      and (
        (c.task_id    is not null and exists (select 1 from public.tasks t where t.id = c.task_id and public.user_can_see_project(t.project_id)))
        or
        (c.project_id is not null and public.user_can_see_project(c.project_id))
      )
  ))
);

-- Insert: any authenticated user can record an attachment they uploaded.
drop policy if exists "attachments_insert" on public.attachments;
create policy "attachments_insert" on public.attachments for insert
  with check (uploaded_by = auth.uid());

-- Delete: any signed-in user can delete any attachment.
drop policy if exists "attachments_delete"     on public.attachments;
drop policy if exists "attachments_delete_all" on public.attachments;
create policy "attachments_delete_all" on public.attachments for delete
  using (auth.uid() is not null);

-- 3) Storage bucket + policies.
insert into storage.buckets (id, name, public)
values ('attachments', 'attachments', false)
on conflict (id) do nothing;

-- Anyone authenticated can read objects (we filter at the app/RLS layer via the attachments table).
drop policy if exists "attachments_storage_read" on storage.objects;
create policy "attachments_storage_read" on storage.objects for select
  using (bucket_id = 'attachments' and auth.uid() is not null);

drop policy if exists "attachments_storage_insert" on storage.objects;
create policy "attachments_storage_insert" on storage.objects for insert
  with check (bucket_id = 'attachments' and auth.uid() is not null);

drop policy if exists "attachments_storage_delete" on storage.objects;
create policy "attachments_storage_delete" on storage.objects for delete
  using (bucket_id = 'attachments' and auth.uid() is not null);


-- ===========================================================================
-- ===== 6/6  ADMIN USERS (Ahmed, Hams, Mera, Martha, Heba)  =================
-- ===========================================================================
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
