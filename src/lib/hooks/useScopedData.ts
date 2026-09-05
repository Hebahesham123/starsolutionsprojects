'use client';

import { useData } from '@/lib/store/data';

// Every user sees every project and task. Kept as a hook so callers don't have
// to change if per-user scoping is ever reintroduced.
export function useScopedData() {
  const data = useData();
  return { ...data, restricted: false };
}
