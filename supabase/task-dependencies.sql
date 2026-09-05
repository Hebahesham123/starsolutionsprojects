-- ============================================================================
-- Task reference code, dependency type and "blocked by" person.
-- Run once in the Supabase SQL editor (safe to re-run).
--
--   task_code   the "#" from the plan, e.g. "1.5" — free text, sorts the list
--   task_type   'DEP' (depends on someone) or 'IND' (independent)
--   blocked_by  who this task is waiting on, e.g. "HEBA & DR AHMED"
-- ============================================================================

alter table public.tasks
  add column if not exists task_code text;

alter table public.tasks
  add column if not exists task_type text;

alter table public.tasks
  add column if not exists blocked_by text;

-- 'DEP' / 'IND' / not set. Re-created each run so the check stays correct.
alter table public.tasks
  drop constraint if exists tasks_task_type_check;
alter table public.tasks
  add constraint tasks_task_type_check
  check (task_type is null or task_type in ('DEP', 'IND'));

create index if not exists idx_tasks_task_code on public.tasks(project_id, task_code);
