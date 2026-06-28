'use client';

import { createClient } from '@/lib/supabase/client';
import type { Notification, Project, Task, UserProfile } from '@/lib/types';

const DAYS_AHEAD = 2;
const LOCK_KEY = 'ns-deadline-scan-lock';

function ymd(d: Date) { return d.toISOString().slice(0, 10); }
function addDays(s: string, n: number) {
  const d = new Date(s);
  d.setDate(d.getDate() + n);
  return ymd(d);
}
/**
 * Scans tasks + projects for deadlines within the next DAYS_AHEAD days and
 * emits in-app notifications. Dedupes via the notifications table — never
 * notifies twice per entity per calendar day.
 *
 * Safe to call on every dashboard mount: client-side localStorage lock
 * prevents re-running within 6 hours from the same browser.
 */
export async function runDeadlineScan(opts: {
  tasks: Task[];
  projects: Project[];
  users: UserProfile[];
  notifications: Notification[];
  currentUserId?: string;
}): Promise<void> {
  if (typeof window === 'undefined') return;
  const now = Date.now();
  const last = Number(localStorage.getItem(LOCK_KEY) ?? 0);
  if (now - last < 6 * 60 * 60 * 1000) return;
  localStorage.setItem(LOCK_KEY, String(now));

  const supabase = createClient();
  const today = ymd(new Date());
  const limit = addDays(today, DAYS_AHEAD);

  // Dedupe key: we tag notif.link with "?deadline=<entity>-<date>"
  const sentToday = new Set(
    opts.notifications
      .filter(n => n.kind === 'deadline_near' && n.created_at.slice(0, 10) === today)
      .map(n => n.link ?? '')
  );

  const queue: Array<{
    userId?: string;
    inApp: { title: string; body?: string; link: string };
  }> = [];

  // ── Tasks ───────────────────────────────────────────────────────────────
  for (const t of opts.tasks) {
    if (!t.due_date || t.status === 'done') continue;
    if (t.due_date < today || t.due_date > limit) continue;
    if (!t.assignee_id && !t.assignee_email) continue;

    const link = `/projects/${t.project_id}?deadline=task-${t.id}-${today}`;
    if (sentToday.has(link)) continue;

    const project = opts.projects.find(p => p.id === t.project_id);
    const days = Math.max(0, Math.round((new Date(t.due_date).getTime() - new Date(today).getTime()) / 86400000));

    queue.push({
      userId: t.assignee_id ?? undefined,
      inApp: {
        title: days === 0 ? `Due today: ${t.title}` : `Due in ${days}d: ${t.title}`,
        body: `Project: ${project?.name ?? '—'}`,
        link,
      },
    });
  }

  // ── Projects ────────────────────────────────────────────────────────────
  for (const p of opts.projects) {
    if (!p.estimated_end_date || p.status === 'completed') continue;
    if (p.estimated_end_date < today || p.estimated_end_date > limit) continue;
    if (!p.owner_email) continue;

    const link = `/projects/${p.id}?deadline=project-${p.id}-${today}`;
    if (sentToday.has(link)) continue;

    const ownerUser = opts.users.find(u => u.email === p.owner_email);
    const days = Math.max(0, Math.round((new Date(p.estimated_end_date).getTime() - new Date(today).getTime()) / 86400000));

    queue.push({
      userId: ownerUser?.id,
      inApp: {
        title: days === 0 ? `Ends today: ${p.name}` : `Ends in ${days}d: ${p.name}`,
        body: `${Math.round(Number(p.completion_rate))}% complete`,
        link,
      },
    });
  }

  if (queue.length === 0) return;

  // Insert in-app rows only for users we know
  const rows = queue
    .filter(q => q.userId)
    .map(q => ({
      user_id: q.userId!,
      kind: 'deadline_near' as const,
      title: q.inApp.title,
      body: q.inApp.body ?? null,
      link: q.inApp.link,
      read: false,
    }));
  if (rows.length) {
    const { error } = await supabase.from('notifications').insert(rows);
    if (error) console.warn('[deadlineScan] insert failed:', error.message);
  }
}
