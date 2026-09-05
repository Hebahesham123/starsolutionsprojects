# Star Solutions

Enterprise-grade project & task management dashboard. Next.js 14 + Supabase + Tailwind + i18n (EN/AR with RTL) + Realtime.

## Quick start

1. `npm install`
2. Create a Supabase project at https://supabase.com
3. Copy `.env.local.example` to `.env.local` and fill in your Supabase URL and anon key
4. In Supabase SQL editor, run the contents of `supabase/schema.sql` to create tables, RLS policies, and triggers
5. `npm run dev` and open http://localhost:3000
6. Sign up — the first user is automatically made admin (via trigger); subsequent users default to `team_member` (promote from the Team page)
7. **(Optional) Load B2C demo data** — after signing up, paste `supabase/seed.sql` into the SQL editor and run it. You'll get 6 realistic projects (MVP e-commerce, mobile app, payments, support portal, marketing, SEO), ~40 tasks across all statuses, sample comments, and notifications. Safe to re-run — it wipes and reseeds the `[SEED]` rows.

## SQL run order (existing database)

Run these in the Supabase SQL editor, in this order. All are safe to re-run.

| # | File | What it does |
|---|------|--------------|
| 1 | `supabase/allow-all-edit.sql` | Lets every signed-in user create/edit/delete any project, task, comment and attachment |
| 2 | `supabase/task-dependencies.sql` | Adds `task_code`, `task_type` (DEP/IND) and `blocked_by` to tasks |
| 3 | `supabase/seed-star-projects.sql` | Loads the 7 real projects and their tasks with assignees and dependencies |

Step 3 never overwrites `status` or `completion_percentage`, so re-running it refreshes the plan text without wiping the team's progress.

## Features

- Projects & Tasks with auto-calculated completion & duration
- Dashboard: KPIs, charts, upcoming deadlines, team workload, recent activity
- Kanban board (drag & drop), Calendar view, List view
- Threaded comments on tasks
- Realtime updates across clients (Supabase subscriptions)
- Notifications center
- Open editing: any signed-in user can create/edit/delete any project, task, comment or attachment. Roles (Admin / Project Manager / Team Member) still gate the Team page — only admins change roles or remove accounts.
- EN / AR with full RTL mirroring
- Dark / Light mode
- CSV & PDF export

## Stack

Next.js 14 (App Router, Server Components) · React 18 · TypeScript · Tailwind CSS · Supabase (Postgres, Auth, Realtime, RLS) · Recharts · dnd-kit · lucide-react · date-fns
