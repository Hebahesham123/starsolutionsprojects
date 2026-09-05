-- ============================================================================
-- Open editing: every signed-in user can create, edit and delete ANY project,
-- task, comment and attachment — at any time.
--
-- Run once in the Supabase SQL editor (safe to re-run).
--
-- NOT changed on purpose: public.users stays admin-only for insert/delete and
-- self-or-admin for update, so ordinary users still cannot change other
-- people's roles or remove accounts. Notifications stay private to their owner.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PROJECTS — anyone signed in can write.
-- ----------------------------------------------------------------------------
drop policy if exists "projects_write"     on public.projects;
drop policy if exists "projects_write_all" on public.projects;
create policy "projects_write_all" on public.projects for all
  using (auth.uid() is not null)
  with check (auth.uid() is not null);

-- ----------------------------------------------------------------------------
-- TASKS — anyone signed in can write (replaces the manager/assignee policies).
-- ----------------------------------------------------------------------------
drop policy if exists "tasks_write_managers" on public.tasks;
drop policy if exists "tasks_update_assignee" on public.tasks;
drop policy if exists "tasks_write_all"      on public.tasks;
create policy "tasks_write_all" on public.tasks for all
  using (auth.uid() is not null)
  with check (auth.uid() is not null);

-- ----------------------------------------------------------------------------
-- COMMENTS — anyone signed in can edit or delete any comment.
-- (There was no UPDATE policy before, so editing a comment always failed.)
-- New comments are still stamped with the real author.
-- ----------------------------------------------------------------------------
drop policy if exists "comments_delete_own" on public.comments;
drop policy if exists "comments_delete_all" on public.comments;
create policy "comments_delete_all" on public.comments for delete
  using (auth.uid() is not null);

drop policy if exists "comments_update_all" on public.comments;
create policy "comments_update_all" on public.comments for update
  using (auth.uid() is not null)
  with check (auth.uid() is not null);

-- ----------------------------------------------------------------------------
-- ATTACHMENTS — anyone signed in can delete any attachment row + its file.
-- ----------------------------------------------------------------------------
drop policy if exists "attachments_delete"     on public.attachments;
drop policy if exists "attachments_delete_all" on public.attachments;
create policy "attachments_delete_all" on public.attachments for delete
  using (auth.uid() is not null);

drop policy if exists "attachments_storage_delete" on storage.objects;
create policy "attachments_storage_delete" on storage.objects for delete
  using (bucket_id = 'attachments' and auth.uid() is not null);

-- ----------------------------------------------------------------------------
-- Sanity check: list the resulting policies.
-- ----------------------------------------------------------------------------
select schemaname, tablename, policyname, cmd
  from pg_policies
 where (schemaname = 'public'  and tablename in ('projects','tasks','comments','attachments'))
    or (schemaname = 'storage' and policyname like 'attachments_storage%')
 order by schemaname, tablename, policyname;
