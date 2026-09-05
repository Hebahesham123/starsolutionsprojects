// Top-level departments shown in the picker.
export const DEPARTMENTS_TOP = [
  'Technology',
] as const;

// Hierarchical groups: parent -> children. Children are themselves valid selectable values.
// Supports nested groups (a child can be a parent in this map).
export const DEPARTMENT_GROUPS: Record<string, readonly string[]> = {};

// Flat list of every valid department value (top-level + all descendants).
// Use this for filter Set membership checks against saved values.
function flattenGroups(top: readonly string[], groups: Record<string, readonly string[]>): string[] {
  const out: string[] = [];
  const walk = (name: string) => {
    out.push(name);
    const kids = groups[name];
    if (kids) kids.forEach(walk);
  };
  top.forEach(walk);
  return out;
}

export const DEPARTMENTS = flattenGroups(DEPARTMENTS_TOP, DEPARTMENT_GROUPS) as readonly string[];

export type Department = string;

// Allowed Project Managers
export const PROJECT_MANAGERS = [
  'Dr. Ahmed',
] as const;

// Allowed Project Owners (the 4 admins)
export const PROJECT_OWNERS = [
  'Karim Elbahey',
  'Rehab Ibrahim',
  'Farah Ashraf',
  'Anjie Magdy',
] as const;

// No user is restricted any more — everyone sees and edits every project/task.
export const RESTRICTED_USER_EMAILS = [] as const;

export function isRestrictedEmail(_email?: string | null) {
  return false;
}
