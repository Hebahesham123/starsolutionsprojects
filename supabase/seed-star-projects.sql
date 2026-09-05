-- ============================================================================
-- Projects & Tasks Tracker — September 2026 plan
-- Loads the 7 projects and their tasks with assignee, type (DEP/IND) and
-- "blocked by" person.
--
-- Run AFTER supabase/task-dependencies.sql (it adds the columns used here).
--
-- SAFE TO RE-RUN: rows are keyed by fixed UUIDs, so a second run updates the
-- plan text instead of creating duplicates — and it deliberately does NOT
-- touch `status`, `completion_percentage` or the dates, so progress the team
-- has already recorded in the app is never overwritten.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Resolve a plan name ("HEBA", "DR AHMED") to a real user account, if one
-- exists. Matches on <name>@starsolutions.com, on the full name, or on the
-- first word of the full name. Returns NULL when the person has no account —
-- the task still keeps their name in `assignee_name`.
-- ----------------------------------------------------------------------------
create or replace function public._person_id(p_key text)
returns uuid
language sql
stable
as $$
  select u.id
    from public.users u
   where lower(u.email) = lower(p_key) || '@starsolutions.com'
      or lower(coalesce(u.full_name, '')) = lower(p_key)
      or split_part(lower(coalesce(u.full_name, '')), ' ', 1) = lower(p_key)
   order by (lower(coalesce(u.full_name, '')) = lower(p_key)) desc,
            u.created_at asc
   limit 1
$$;

-- ============================================================================
-- PROJECTS
-- ============================================================================
insert into public.projects (id, name, start_date, created_by)
select v.id, v.name, current_date,
       coalesce(public._person_id('heba'), (select id from public.users order by created_at asc limit 1))
  from (values
    ('b0000000-0000-0000-0000-000000000001'::uuid, 'E-commerce'),
    ('b0000000-0000-0000-0000-000000000002'::uuid, 'Black Friday UI'),
    ('b0000000-0000-0000-0000-000000000003'::uuid, 'KA'),
    ('b0000000-0000-0000-0000-000000000004'::uuid, 'Hollywood Clinic'),
    ('b0000000-0000-0000-0000-000000000005'::uuid, 'Beauty Bar'),
    ('b0000000-0000-0000-0000-000000000006'::uuid, 'StarSolution'),
    ('b0000000-0000-0000-0000-000000000007'::uuid, 'Montre USA'),
    ('b0000000-0000-0000-0000-000000000008'::uuid, 'Courier App')
  ) as v(id, name)
on conflict (id) do update set
  name = excluded.name;
  -- status / completion_rate / dates left alone on purpose.

-- ============================================================================
-- TASKS
--   code | title | deliverable | person_key | assignee label | type | blocked by
--   "└" marks a sub-task of the task above it, as in the original plan.
-- ============================================================================
insert into public.tasks (
  id, project_id, task_code, title, description,
  assignee_id, assignee_name, assignee_email,
  task_type, blocked_by, order_index, created_by
)
select
  v.id, v.project_id, v.code, v.title, v.deliverable,
  u.id, v.assignee_label, u.email,
  v.ttype, v.blocked, v.ord,
  coalesce(public._person_id('heba'), (select id from public.users order by created_at asc limit 1))
from (values
  -- ---- Project 1 — E-commerce -------------------------------------------
  ('c0000000-0000-0000-0000-000000010001'::uuid, 'b0000000-0000-0000-0000-000000000001'::uuid, '1.1',  'Finance',                              'Pricing, tax, refund & points rules',        'heba',   'HEBA & MERA',                'DEP', 'HEBA',            1),
  ('c0000000-0000-0000-0000-000000010002'::uuid, 'b0000000-0000-0000-0000-000000000001'::uuid, '1.2',  '└ Payment methods integration',        'Gateways live in test + production',         'heba',   'HEBA',                       'IND', null,              2),
  ('c0000000-0000-0000-0000-000000010003'::uuid, 'b0000000-0000-0000-0000-000000000001'::uuid, '1.3',  '└ Accounting system',                  'Auto invoice per order',                     'heba',   'HEBA',                       'IND', null,              3),
  ('c0000000-0000-0000-0000-000000010004'::uuid, 'b0000000-0000-0000-0000-000000000001'::uuid, '1.4',  'App UI — all pages',                   'Home, product, collection, customer',        'heba',   'HEBA & MARTHA',              'DEP', 'HEBA & DR AHMED', 4),
  ('c0000000-0000-0000-0000-000000010005'::uuid, 'b0000000-0000-0000-0000-000000000001'::uuid, '1.5',  '└ Loyalty UI',                         'Balance, earn / redeem, tiers',              'heba',   'LOGIC: HEBA / UI: MARTHA',   'DEP', 'HEBA',            5),
  ('c0000000-0000-0000-0000-000000010006'::uuid, 'b0000000-0000-0000-0000-000000000001'::uuid, '1.6',  '└ Customer account UI',                'Orders, addresses, profile, loyalty tab',    'mera',   'MERA',                       'DEP', 'HEBA',            6),
  ('c0000000-0000-0000-0000-000000010007'::uuid, 'b0000000-0000-0000-0000-000000000001'::uuid, '1.7',  '└ Meta integration',                   'Pixel, CAPI, catalog feed',                  'hams',   'HAMS',                       'IND', null,              7),
  ('c0000000-0000-0000-0000-000000010008'::uuid, 'b0000000-0000-0000-0000-000000000001'::uuid, '1.8',  'Products & inventory sync APP',        'Live product / stock sync',                  'hams',   'HAMS',                       'DEP', 'HEBA',            8),
  ('c0000000-0000-0000-0000-000000010009'::uuid, 'b0000000-0000-0000-0000-000000000001'::uuid, '1.9',  '└ Dashboard — orders',                 'Order list, detail, status change',          'heba',   'HEBA',                       'DEP', 'HAMS',            9),
  ('c0000000-0000-0000-0000-000000010010'::uuid, 'b0000000-0000-0000-0000-000000000001'::uuid, '1.10', '└ Courier automation',                 'Auto-dispatch + AWB',                        'heba',   'HEBA',                       'DEP', 'HAMS',           10),
  ('c0000000-0000-0000-0000-000000010011'::uuid, 'b0000000-0000-0000-0000-000000000001'::uuid, '1.11', '└ Delivery status (dashboard + site)', 'Live tracking on both surfaces',             'mera',   'MERA',                       'DEP', 'HAMS',           11),
  ('c0000000-0000-0000-0000-000000010012'::uuid, 'b0000000-0000-0000-0000-000000000001'::uuid, '1.12', 'Testing',                              'Test cases, bug log, sign-off',              'mariam', 'MARIAM',                     'DEP', 'HEBA',           12),

  -- ---- Project 2 — Black Friday UI ---------------------------------------
  ('c0000000-0000-0000-0000-000000020001'::uuid, 'b0000000-0000-0000-0000-000000000002'::uuid, '2.1',  'Black Friday UI',                      'Banners, badges, countdown, landing page',   'martha', 'MARTHA',                     'DEP', 'HEBA & DR AHMED', 1),

  -- ---- Project 3 — KA -----------------------------------------------------
  ('c0000000-0000-0000-0000-000000030001'::uuid, 'b0000000-0000-0000-0000-000000000003'::uuid, '3.1',  'KA UI',                                'Full site UI, limestone / Pharaonic direction', 'mera', 'MERA',                    'DEP', 'HEBA & MARTHA',   1),

  -- ---- Project 4 — Hollywood Clinic ---------------------------------------
  ('c0000000-0000-0000-0000-000000040001'::uuid, 'b0000000-0000-0000-0000-000000000004'::uuid, '4.1',  'n8n confirmation flow',                'Confirmation + rescheduling live',           'hams',   'HAMS & MARTHA',              'DEP', 'HAMS',            1),
  ('c0000000-0000-0000-0000-000000040002'::uuid, 'b0000000-0000-0000-0000-000000000004'::uuid, '4.2',  'n8n follow-up flow',                   'Post-session follow-up + review live',       'hams',   'HAMS & MARTHA',              'DEP', 'HAMS',            2),
  ('c0000000-0000-0000-0000-000000040003'::uuid, 'b0000000-0000-0000-0000-000000000004'::uuid, '4.3',  'SEO — 10 keywords',                    'Keyword map + on-page work',                 'mera',   'MERA',                       'IND', null,              3),
  ('c0000000-0000-0000-0000-000000040004'::uuid, 'b0000000-0000-0000-0000-000000000004'::uuid, '4.4',  'Accounting system',                    'Auto invoice per order',                     'heba',   'HEBA',                       'IND', null,              4),

  -- ---- Project 5 — Beauty Bar ---------------------------------------------
  ('c0000000-0000-0000-0000-000000050001'::uuid, 'b0000000-0000-0000-0000-000000000005'::uuid, '5.1',  'SEO — 10 keywords',                    'Research + on-page implementation',          'heba',   'HEBA',                       'IND', null,              1),
  ('c0000000-0000-0000-0000-000000050002'::uuid, 'b0000000-0000-0000-0000-000000000005'::uuid, '5.2',  '└ SEO — 5 products',                   '5 pages: title, meta, copy, schema',         'heba',   'HEBA & MARTHA',              'DEP', 'HEBA',            2),
  ('c0000000-0000-0000-0000-000000050003'::uuid, 'b0000000-0000-0000-0000-000000000005'::uuid, '5.3',  'Accounting system',                    'Auto invoice per order',                     'heba',   'HEBA',                       'IND', null,              3),

  -- ---- Project 6 — StarSolution -------------------------------------------
  ('c0000000-0000-0000-0000-000000060001'::uuid, 'b0000000-0000-0000-0000-000000000006'::uuid, '6.1',  'Website launch',                       'Live on the real domain',                    'martha', 'MARTHA',                     'DEP', 'DR AHMED',        1),
  ('c0000000-0000-0000-0000-000000060002'::uuid, 'b0000000-0000-0000-0000-000000000006'::uuid, '6.2',  '└ Meta integration',                   'Pixel, CAPI, lead-form events',              'martha', 'MARTHA',                     'DEP', 'HAMS',            2),
  ('c0000000-0000-0000-0000-000000060003'::uuid, 'b0000000-0000-0000-0000-000000000006'::uuid, '6.3',  '└ Dashboard',                          'Leads / results dashboard on Supabase',      'martha', 'MARTHA',                     'DEP', 'HEBA',            3),
  ('c0000000-0000-0000-0000-000000060004'::uuid, 'b0000000-0000-0000-0000-000000000006'::uuid, '6.4',  'Pick 2 services to push',              'Written decision + offer for each',          'martha', 'MARTHA',                     'DEP', 'HEBA',            4),
  ('c0000000-0000-0000-0000-000000060005'::uuid, 'b0000000-0000-0000-0000-000000000006'::uuid, '6.5',  '└ Advertising — the 2 services',       'Creatives + live campaigns',                 'ahmed',  'DR AHMED',                   'IND', null,              5),
  ('c0000000-0000-0000-0000-000000060006'::uuid, 'b0000000-0000-0000-0000-000000000006'::uuid, '6.6',  '└ Social media',                       'Content calendar + published posts',         'martha', 'MARTHA',                     'DEP', 'GANNA',           6),

  -- ---- Project 7 — Montre USA ---------------------------------------------
  ('c0000000-0000-0000-0000-000000070001'::uuid, 'b0000000-0000-0000-0000-000000000007'::uuid, '7.1',  'Image editing',                        'Edited product images, final set',           'mera',   'MERA',                       'IND', null,              1),
  ('c0000000-0000-0000-0000-000000070002'::uuid, 'b0000000-0000-0000-0000-000000000007'::uuid, '7.2',  'n8n ordering system flow',             'Order intake → confirmation workflow',       'heba',   'HEBA',                       'IND', null,              2),
  ('c0000000-0000-0000-0000-000000070003'::uuid, 'b0000000-0000-0000-0000-000000000007'::uuid, '7.3',  '└ Payment link',                       'Auto payment link + reminders',              'heba',   'HEBA',                       'IND', null,              3),

  -- ---- Project 8 — Courier App --------------------------------------------
  ('c0000000-0000-0000-0000-000000080001'::uuid, 'b0000000-0000-0000-0000-000000000008'::uuid, '8.1',  'Courier App',                          null,                                         'mera',   'MERA',                       'DEP', 'HEBA',            1)
) as v(id, project_id, code, title, deliverable, person_key, assignee_label, ttype, blocked, ord)
left join lateral (
  select usr.id, usr.email
    from public.users usr
   where usr.id = public._person_id(v.person_key)
) u on true
on conflict (id) do update set
  project_id     = excluded.project_id,
  task_code      = excluded.task_code,
  title          = excluded.title,
  description    = excluded.description,
  assignee_id    = excluded.assignee_id,
  assignee_name  = excluded.assignee_name,
  assignee_email = excluded.assignee_email,
  task_type      = excluded.task_type,
  blocked_by     = excluded.blocked_by,
  order_index    = excluded.order_index;
  -- status and completion_percentage are deliberately NOT overwritten,
  -- so whatever the team has set in the app survives a re-run.

-- ============================================================================
-- Check what landed — and who still has no account (assignee_email is null).
-- ============================================================================
select p.name as project, t.task_code, t.title, t.assignee_name,
       t.assignee_email, t.task_type, t.blocked_by, t.status
  from public.tasks t
  join public.projects p on p.id = t.project_id
 where t.id::text like 'c0000000-%'
 order by p.name, t.order_index;
