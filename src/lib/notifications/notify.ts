import { createClient } from '@/lib/supabase/client';
import type { Notification } from '@/lib/types';

type Kind = Notification['kind'];

export type NotifyArgs = {
  userId: string;
  kind: Kind;
  title: string;
  body?: string;
  link?: string;
};

/** Insert an in-app notification (the bell). Email sending has been removed. */
export async function notify(args: NotifyArgs): Promise<void> {
  const supabase = createClient();

  const { error } = await supabase.from('notifications').insert({
    user_id: args.userId,
    kind: args.kind,
    title: args.title,
    body: args.body ?? null,
    link: args.link ?? null,
    read: false,
  });
  if (error) console.warn('[notify] insert failed:', error.message);
}
