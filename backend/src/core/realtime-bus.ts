/**
 * In-memory pub/sub for realtime per-user events that get pushed to
 * connected SSE clients in `GET /api/v1/sync/stream`.
 *
 * Design choices:
 *
 *  - Keyed by `userId` so we never leak data across accounts: a publish
 *    to user A is only visible to listeners of user A.
 *  - In-memory (single-process). Suitable for the current single-replica
 *    deployment. The day we shard across Node instances this gets
 *    swapped for a Redis pub/sub bridge; the public surface
 *    (`subscribe` / `publish` / `RealtimeEvent`) stays the same so the
 *    HTTP layer is decoupled from the transport.
 *  - `subscribe` returns an unsubscribe function, NOT an EventEmitter
 *    handle, so leaks from "I forgot which listener I added" are
 *    impossible: the only way to stop listening is to call the closure
 *    you got back. Tests rely on this for cleanup.
 */

export type RealtimeEventType =
  | 'progress.updated'
  | 'bookmark.added'
  | 'bookmark.updated'
  | 'bookmark.removed';

export interface RealtimeEvent<T = unknown> {
  type: RealtimeEventType;
  /** Sentinel for the device that originated the write. Clients use it
   *  to discard their own echoes. Optional — server-side maintenance
   *  events have no originator. */
  clientId?: string;
  /** ISO-8601 server timestamp at publish time. Clients use it to
   *  resolve concurrent edits (last-write-wins). */
  ts: string;
  data: T;
}

type Listener = (event: RealtimeEvent) => void;

export class RealtimeBus {
  private listeners = new Map<string, Set<Listener>>();

  subscribe(userId: string, listener: Listener): () => void {
    let set = this.listeners.get(userId);
    if (!set) {
      set = new Set();
      this.listeners.set(userId, set);
    }
    set.add(listener);

    return () => {
      const current = this.listeners.get(userId);
      if (!current) return;
      current.delete(listener);
      if (current.size === 0) this.listeners.delete(userId);
    };
  }

  /** Returns the number of listeners that received the event. Useful
   *  for tests and observability. */
  publish(userId: string, event: Omit<RealtimeEvent, 'ts'>): number {
    const set = this.listeners.get(userId);
    if (!set || set.size === 0) return 0;

    const enriched: RealtimeEvent = { ...event, ts: new Date().toISOString() };
    let count = 0;
    for (const listener of set) {
      try {
        listener(enriched);
        count++;
      } catch (err) {
        // A listener that throws must not stop delivery to the rest.
        // Surfaced through console.error to keep this file dependency-free
        // (Fastify logger lives in the request scope, not here).
        // eslint-disable-next-line no-console
        console.error('[RealtimeBus] listener threw:', err);
      }
    }
    return count;
  }

  /** Diagnostic accessors. Useful for tests and the `/health` endpoint
   *  if we ever want to expose connection counts. */
  listenerCount(userId: string): number {
    return this.listeners.get(userId)?.size ?? 0;
  }

  totalListenerCount(): number {
    let total = 0;
    for (const set of this.listeners.values()) total += set.size;
    return total;
  }

  /** Wipe everything. Test helper; never used in production. */
  reset(): void {
    this.listeners.clear();
  }
}

/** Singleton instance shared by the SSE endpoint and the mutation
 *  handlers. Importing this directly avoids threading the bus through
 *  every route handler. */
export const realtimeBus = new RealtimeBus();
