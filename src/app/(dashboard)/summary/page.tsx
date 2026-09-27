'use client';

import React, { useMemo } from 'react';
import Link from 'next/link';
import { ChevronLeft, ChevronRight, Download, ClipboardList, Search } from 'lucide-react';
import { addMonths, format, subMonths } from 'date-fns';
import { useData } from '@/lib/store/data';
import { useScopedData } from '@/lib/hooks/useScopedData';
import { usePersistentState } from '@/lib/hooks/usePersistentState';
import { useI18n } from '@/lib/i18n/LanguageProvider';
import { Card, CardBody } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Select } from '@/components/ui/Input';
import { Avatar } from '@/components/ui/Avatar';
import { Progress } from '@/components/ui/Progress';
import { Skeleton } from '@/components/ui/Skeleton';
import { EmptyState } from '@/components/ui/EmptyState';
import { ProjectStatusBadge, TaskStatusBadge } from '@/components/projects/StatusBadge';
import { formatDate, cn, uniquePeople, splitPeople } from '@/lib/utils';
import type { Task, TaskType } from '@/lib/types';

const ALL = 'all';

/**
 * Only this person's filter also pulls in the tasks that are waiting on them.
 * Everyone else's filter shows just the tasks assigned to them.
 */
const DEPENDENCY_PERSON = 'heba';

const avgOf = (list: Task[]) =>
  list.length ? Math.round(list.reduce((sum, x) => sum + x.completion_percentage, 0) / list.length) : 0;

/** yyyy-MM of a date-ish string, or null. */
function monthKeyOf(iso?: string | null) {
  return iso ? iso.slice(0, 7) : null;
}

/**
 * A task counts towards a month when its work overlaps that month:
 *   - it starts or is due inside the month, or
 *   - it spans right across the month, or
 *   - it has no dates at all, in which case we fall back to when it was created.
 */
function taskInMonth(task: Task, monthKey: string) {
  const start = monthKeyOf(task.start_date);
  const due = monthKeyOf(task.due_date);
  if (!start && !due) return monthKeyOf(task.created_at) === monthKey;
  if (start === monthKey || due === monthKey) return true;
  if (start && due) return start < monthKey && due > monthKey;
  return false;
}

function TypeBadge({ type }: { type: TaskType }) {
  return (
    <span
      title={type === 'DEP' ? 'Depends on someone else' : 'Independent — can start any time'}
      className={cn(
        'shrink-0 rounded-md px-1.5 py-0.5 text-[10px] font-semibold',
        type === 'DEP'
          ? 'bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-400'
          : 'bg-emerald-100 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-400'
      )}
    >
      {type}
    </span>
  );
}

function Stat({ label, value, tone }: { label: string; value: React.ReactNode; tone?: string }) {
  return (
    <div className="rounded-xl border border-slate-200 px-3 py-2 dark:border-slate-800">
      <div className="text-[11px] uppercase tracking-wider text-slate-500">{label}</div>
      <div className={cn('mt-0.5 text-lg font-bold text-slate-900 dark:text-slate-100', tone)}>{value}</div>
    </div>
  );
}

export default function SummaryPage() {
  const { t } = useI18n();
  const { hydrated } = useData();
  const { projects, tasks } = useScopedData();

  const thisMonth = format(new Date(), 'yyyy-MM');
  const [month, setMonth] = usePersistentState<string>('summary.month', thisMonth);
  const [projectId, setProjectId] = usePersistentState<string>('summary.project', ALL);
  const [status, setStatus] = usePersistentState<string>('summary.status', ALL);
  const [assignee, setAssignee] = usePersistentState<string>('summary.assignee', ALL);
  const [q, setQ] = usePersistentState<string>('summary.q', '');

  const selectedKey = assignee === ALL ? null : assignee.toLowerCase();
  // True when the selected person's view also carries the tasks waiting on them.
  const showsDependents = selectedKey === DEPENDENCY_PERSON;
  const isOwnedBySelected = (task: Task) =>
    !!selectedKey && splitPeople(task.assignee_name).some(p => p.toLowerCase() === selectedKey);

  const isAllTime = month === ALL;
  const cursor = isAllTime ? new Date() : new Date(`${month}-01T00:00:00`);

  // Every month that actually has something in it, newest first.
  const monthOptions = useMemo(() => {
    const set = new Set<string>([thisMonth]);
    for (const task of tasks) {
      for (const d of [task.start_date, task.due_date, task.created_at]) {
        const key = monthKeyOf(d);
        if (key) set.add(key);
      }
    }
    return Array.from(set).sort().reverse();
  }, [tasks, thisMonth]);

  // Individual people, pulled out of labels like "HEBA & MERA". Includes people
  // who only ever appear as a blocker, so they are still selectable.
  const assigneeOptions = useMemo(
    () =>
      uniquePeople([
        ...tasks.map(x => x.assignee_name),
        ...tasks.map(x => x.blocked_by),
      ]).sort((a, b) => a.localeCompare(b)),
    [tasks]
  );

  const monthTasks = useMemo(() => {
    let list = isAllTime ? tasks : tasks.filter(task => taskInMonth(task, month));
    if (projectId !== ALL) list = list.filter(x => x.project_id === projectId);
    if (status !== ALL) list = list.filter(x => x.status === status);
    if (assignee !== ALL) {
      const who = assignee.toLowerCase();
      const withDependents = who === DEPENDENCY_PERSON;
      list = list.filter(
        x =>
          splitPeople(x.assignee_name).some(p => p.toLowerCase() === who) ||
          (withDependents && splitPeople(x.blocked_by).some(p => p.toLowerCase() === who))
      );
    }
    if (q.trim()) {
      const needle = q.trim().toLowerCase();
      list = list.filter(
        x =>
          x.title.toLowerCase().includes(needle) ||
          x.description?.toLowerCase().includes(needle) ||
          x.assignee_name?.toLowerCase().includes(needle) ||
          x.blocked_by?.toLowerCase().includes(needle) ||
          x.task_code?.toLowerCase().includes(needle)
      );
    }
    return list;
  }, [tasks, month, isAllTime, projectId, status, assignee, q]);

  // Group into project -> its tasks, keeping the plan's own order.
  const groups = useMemo(() => {
    const byProject = new Map<string, Task[]>();
    for (const task of monthTasks) {
      const arr = byProject.get(task.project_id) ?? [];
      arr.push(task);
      byProject.set(task.project_id, arr);
    }
    return projects
      .filter(p => byProject.has(p.id))
      .map(p => {
        const list = (byProject.get(p.id) ?? []).sort(
          (a, b) => a.order_index - b.order_index || (a.created_at < b.created_at ? -1 : 1)
        );
        const avg = list.length
          ? Math.round(list.reduce((sum, x) => sum + x.completion_percentage, 0) / list.length)
          : 0;
        return {
          project: p,
          tasks: list,
          done: list.filter(x => x.status === 'done').length,
          blocked: list.filter(x => x.status === 'blocked').length,
          active: list.filter(x => x.status === 'in_progress' || x.status === 'on_going').length,
          avg,
          owners: uniquePeople(list.map(x => x.assignee_name)),
          blockers: uniquePeople(list.map(x => x.blocked_by)),
          own: list.filter(isOwnedBySelected),
          ownAvg: avgOf(list.filter(isOwnedBySelected)),
        };
      })
      .sort((a, b) => a.project.name.localeCompare(b.project.name));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [monthTasks, projects, selectedKey]);

  const totals = useMemo(() => {
    const all = monthTasks;
    const own = all.filter(isOwnedBySelected);
    return {
      projects: groups.length,
      tasks: all.length,
      done: all.filter(x => x.status === 'done').length,
      active: all.filter(x => x.status === 'in_progress' || x.status === 'on_going').length,
      blocked: all.filter(x => x.status === 'blocked').length,
      avg: avgOf(all),
      ownTasks: own.length,
      ownAvg: avgOf(own),
      ownProjects: new Set(own.map(x => x.project_id)).size,
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [monthTasks, groups, selectedKey]);

  const periodLabel = isAllTime ? 'All time' : format(cursor, 'MMMM yyyy');

  const rowsForExport = () =>
    groups.flatMap(g =>
      g.tasks.map(task => ({
        project: g.project.name,
        code: task.task_code ?? '',
        task: task.title,
        deliverable: task.description ?? '',
        assignee: task.assignee_name ?? '',
        type: task.task_type ?? '',
        blocked_by: task.blocked_by ?? '',
        status: task.status,
        completion: `${task.completion_percentage}%`,
        start: formatDate(task.start_date),
        due: formatDate(task.due_date),
      }))
    );

  const doExportCsv = async () => {
    const { exportCsv } = await import('@/lib/export');
    exportCsv(rowsForExport(), `summary-${isAllTime ? 'all-time' : month}`);
  };

  const doExportPdf = async () => {
    const { exportPdf } = await import('@/lib/export');
    exportPdf(
      rowsForExport(),
      [
        { header: 'Project', key: 'project' },
        { header: '#', key: 'code' },
        { header: 'Task', key: 'task' },
        { header: 'Deliverable', key: 'deliverable' },
        { header: 'Assignee', key: 'assignee' },
        { header: 'Type', key: 'type' },
        { header: 'Blocked by', key: 'blocked_by' },
        { header: 'Status', key: 'status' },
        { header: '%', key: 'completion' },
        { header: 'Start', key: 'start' },
        { header: 'Due', key: 'due' },
      ],
      `summary-${isAllTime ? 'all-time' : month}`,
      `Monthly Summary — ${periodLabel}`
    );
  };

  const stepMonth = (delta: number) => {
    const base = isAllTime ? new Date() : cursor;
    setMonth(format(delta < 0 ? subMonths(base, 1) : addMonths(base, 1), 'yyyy-MM'));
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">{t('nav.summary')}</h1>
          <p className="mt-1 text-sm text-slate-500">
            {periodLabel} · {totals.projects} projects · {totals.tasks} tasks
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button variant="outline" size="sm" onClick={doExportCsv}><Download className="h-4 w-4" />CSV</Button>
          <Button variant="outline" size="sm" onClick={doExportPdf}><Download className="h-4 w-4" />PDF</Button>
        </div>
      </div>

      {/* Filters */}
      <div className="flex flex-col gap-3 rounded-2xl border border-slate-200 bg-white p-3 dark:border-slate-800 dark:bg-slate-900 sm:flex-row sm:flex-wrap sm:items-center">
        <div className="flex items-center gap-1">
          <button
            onClick={() => stepMonth(-1)}
            aria-label="Previous month"
            className="rounded-lg border border-slate-200 p-2 text-slate-600 hover:bg-slate-50 dark:border-slate-700 dark:text-slate-300 dark:hover:bg-slate-800"
          >
            <ChevronLeft className="h-4 w-4 rtl-flip" />
          </button>
          <Select value={month} onChange={e => setMonth(e.target.value)} className="w-44">
            <option value={ALL}>All time</option>
            {monthOptions.map(m => (
              <option key={m} value={m}>{format(new Date(`${m}-01T00:00:00`), 'MMMM yyyy')}</option>
            ))}
          </Select>
          <button
            onClick={() => stepMonth(1)}
            aria-label="Next month"
            className="rounded-lg border border-slate-200 p-2 text-slate-600 hover:bg-slate-50 dark:border-slate-700 dark:text-slate-300 dark:hover:bg-slate-800"
          >
            <ChevronRight className="h-4 w-4 rtl-flip" />
          </button>
        </div>

        <Select value={projectId} onChange={e => setProjectId(e.target.value)} className="sm:w-52">
          <option value={ALL}>All projects</option>
          {projects.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
        </Select>

        <Select value={status} onChange={e => setStatus(e.target.value)} className="sm:w-44">
          <option value={ALL}>All statuses</option>
          <option value="todo">{t('task_status.todo')}</option>
          <option value="in_progress">{t('task_status.in_progress')}</option>
          <option value="on_going">{t('task_status.on_going')}</option>
          <option value="done">{t('task_status.done')}</option>
          <option value="blocked">{t('task_status.blocked')}</option>
        </Select>

        <Select value={assignee} onChange={e => setAssignee(e.target.value)} className="sm:w-48">
          <option value={ALL}>All assignees</option>
          {assigneeOptions.map(person => <option key={person} value={person}>{person}</option>)}
        </Select>

        <div className="relative flex-1 min-w-[180px]">
          <Search className="pointer-events-none absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
          <input
            placeholder={t('common.search')}
            value={q}
            onChange={e => setQ(e.target.value)}
            className="h-10 w-full rounded-xl border border-slate-200 bg-white ps-9 pe-3 text-sm placeholder:text-slate-400 focus:border-brand-500 focus:outline-none focus:ring-4 focus:ring-brand-500/10 dark:border-slate-700 dark:bg-slate-900"
          />
        </div>

        {(projectId !== ALL || status !== ALL || assignee !== ALL || q) && (
          <button
            type="button"
            onClick={() => { setProjectId(ALL); setStatus(ALL); setAssignee(ALL); setQ(''); }}
            className="rounded-xl border border-slate-200 px-3 py-2 text-sm text-slate-600 hover:bg-slate-50 dark:border-slate-700 dark:text-slate-300 dark:hover:bg-slate-800"
          >
            Clear
          </button>
        )}
      </div>

      {/* Own vs. including-dependents progress, for the dependency person only */}
      {showsDependents && (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="rounded-2xl border border-slate-200 bg-white p-4 dark:border-slate-800 dark:bg-slate-900">
            <div className="text-[11px] uppercase tracking-wider text-slate-500">
              {assignee} — own tasks
            </div>
            <div className="mt-1 flex items-center gap-3">
              <Progress value={totals.ownAvg} className="flex-1" />
              <span className="text-xl font-bold text-slate-900 dark:text-slate-100">{totals.ownAvg}%</span>
            </div>
            <div className="mt-1 text-xs text-slate-500">
              {totals.ownTasks} tasks across {totals.ownProjects} projects
            </div>
          </div>
          <div className="rounded-2xl border border-slate-200 bg-white p-4 dark:border-slate-800 dark:bg-slate-900">
            <div className="text-[11px] uppercase tracking-wider text-slate-500">
              {assignee} — own + dependent tasks
            </div>
            <div className="mt-1 flex items-center gap-3">
              <Progress value={totals.avg} className="flex-1" />
              <span className="text-xl font-bold text-slate-900 dark:text-slate-100">{totals.avg}%</span>
            </div>
            <div className="mt-1 text-xs text-slate-500">
              {totals.tasks} tasks across {totals.projects} projects · includes {totals.tasks - totals.ownTasks} waiting on {assignee}
            </div>
          </div>
        </div>
      )}

      {/* Month totals */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        <Stat label="Projects" value={totals.projects} />
        <Stat label="Tasks" value={totals.tasks} />
        <Stat label="Done" value={totals.done} tone="text-emerald-600 dark:text-emerald-400" />
        <Stat label="In progress" value={totals.active} tone="text-brand-600 dark:text-brand-400" />
        <Stat label="Blocked" value={totals.blocked} tone="text-rose-600 dark:text-rose-400" />
        <Stat label="Avg. completion" value={`${totals.avg}%`} />
      </div>

      {!hydrated ? (
        <div className="space-y-3">{[0, 1, 2].map(i => <Skeleton key={i} className="h-40" />)}</div>
      ) : groups.length === 0 ? (
        <EmptyState icon={<ClipboardList className="h-8 w-8" />} title={`Nothing in ${periodLabel}`} />
      ) : (
        <div className="space-y-5">
          {groups.map(g => (
            <Card key={g.project.id} className="overflow-hidden p-0">
              {/* Project header */}
              <div className="flex flex-col gap-3 border-b border-slate-200 bg-slate-50/70 px-4 py-3 dark:border-slate-800 dark:bg-slate-900/50 sm:flex-row sm:items-center sm:justify-between">
                <div className="min-w-0">
                  <Link
                    href={`/projects/${g.project.id}`}
                    className="text-base font-semibold text-slate-900 hover:text-brand-600 dark:text-slate-100"
                  >
                    {g.project.name}
                  </Link>
                  <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-slate-500">
                    <ProjectStatusBadge status={g.project.status} />
                    <span>{g.tasks.length} tasks · {g.done} done · {g.active} in progress{g.blocked ? ` · ${g.blocked} blocked` : ''}</span>
                    {g.owners.length > 0 && (
                      <span>Owner: <span className="font-medium text-slate-700 dark:text-slate-200">{g.owners.join(', ')}</span></span>
                    )}
                    {g.blockers.length > 0 && (
                      <span className="text-amber-600 dark:text-amber-400">Blocked by: {g.blockers.join(', ')}</span>
                    )}
                  </div>
                </div>
                <div className="sm:w-56">
                  {showsDependents && g.own.length > 0 && (
                    <div className="mb-1 flex items-center gap-2">
                      <span className="w-20 shrink-0 text-[10px] uppercase tracking-wider text-slate-500">own {g.own.length}</span>
                      <Progress value={g.ownAvg} className="flex-1" />
                      <span className="w-10 text-end text-xs font-bold">{g.ownAvg}%</span>
                    </div>
                  )}
                  <div className="flex items-center gap-2">
                    {showsDependents && (
                      <span className="w-20 shrink-0 text-[10px] uppercase tracking-wider text-slate-500">all {g.tasks.length}</span>
                    )}
                    <Progress value={g.avg} className="flex-1" />
                    <span className="w-10 text-end text-sm font-bold">{g.avg}%</span>
                  </div>
                </div>
              </div>

              {/* Task detail */}
              <CardBody className="p-0">
                <table className="min-w-full table-fixed divide-y divide-slate-200 text-sm dark:divide-slate-800">
                  <thead className="bg-white dark:bg-slate-900">
                    <tr className="text-[10px] font-semibold uppercase tracking-wider text-slate-500">
                      <th className="w-12 px-3 py-2 text-start">#</th>
                      <th className="px-3 py-2 text-start">Task &amp; deliverable</th>
                      <th className="w-40 px-3 py-2 text-start">Assignee</th>
                      <th className="w-28 px-3 py-2 text-start">Blocked by</th>
                      <th className="w-28 px-3 py-2 text-start">Status</th>
                      <th className="w-28 px-3 py-2 text-start">Progress</th>
                      <th className="w-32 px-3 py-2 text-start">Dates</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
                    {g.tasks.map(task => {
                      const today = new Date().toISOString().slice(0, 10);
                      const overdue = task.due_date && task.due_date < today && task.status !== 'done';
                      // Surfaced because the filtered person is blocking it, not doing it.
                      const waitingOnPerson =
                        showsDependents &&
                        !splitPeople(task.assignee_name).some(x => x.toLowerCase() === assignee.toLowerCase()) &&
                        splitPeople(task.blocked_by).some(x => x.toLowerCase() === assignee.toLowerCase());
                      return (
                        <tr key={task.id} className="align-top hover:bg-slate-50 dark:hover:bg-slate-800/60">
                          <td className="px-3 py-2.5 font-mono text-xs text-slate-400">{task.task_code ?? '—'}</td>
                          <td className="px-3 py-2.5">
                            <div className="flex items-start gap-2">
                              <Link href={`/projects/${task.project_id}`} className="font-medium text-slate-900 hover:text-brand-600 dark:text-slate-100">
                                {task.title}
                              </Link>
                              {task.task_type && <TypeBadge type={task.task_type} />}
                              {waitingOnPerson && (
                                <span className="shrink-0 rounded-md bg-rose-100 px-1.5 py-0.5 text-[10px] font-semibold text-rose-700 dark:bg-rose-500/15 dark:text-rose-400">
                                  waiting on {assignee}
                                </span>
                              )}
                            </div>
                            {task.description && (
                              <div className="mt-0.5 text-xs text-slate-500">{task.description}</div>
                            )}
                            {(task.departments ?? []).length > 0 && (
                              <div className="mt-1 flex flex-wrap gap-1">
                                {(task.departments ?? []).map(d => (
                                  <span key={d} className="rounded bg-slate-100 px-1.5 py-0.5 text-[10px] text-slate-600 dark:bg-slate-800 dark:text-slate-300">{d}</span>
                                ))}
                              </div>
                            )}
                          </td>
                          <td className="px-3 py-2.5">
                            {task.assignee_name ? (
                              <div className="flex items-center gap-1.5">
                                <Avatar size={20} name={task.assignee_name} email={task.assignee_email} />
                                <span className="text-xs text-slate-700 dark:text-slate-200">{task.assignee_name}</span>
                              </div>
                            ) : <span className="text-slate-400">—</span>}
                          </td>
                          <td className="px-3 py-2.5 text-xs">
                            {task.blocked_by
                              ? <span className="font-medium text-amber-600 dark:text-amber-400">{task.blocked_by}</span>
                              : <span className="text-slate-400">—</span>}
                          </td>
                          <td className="px-3 py-2.5"><TaskStatusBadge status={task.status} /></td>
                          <td className="px-3 py-2.5">
                            <div className="flex items-center gap-1.5">
                              <Progress value={task.completion_percentage} className="w-14" />
                              <span className="text-xs font-semibold">{task.completion_percentage}%</span>
                            </div>
                          </td>
                          <td className="px-3 py-2.5 text-xs">
                            <div className="text-slate-600 dark:text-slate-300">{formatDate(task.start_date, 'MMM d')}</div>
                            <div className={cn(overdue ? 'font-semibold text-rose-600' : 'text-slate-500')}>
                              {task.due_date ? `due ${formatDate(task.due_date, 'MMM d')}` : 'no due date'}
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </CardBody>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
