import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase, type MoneyHubClient } from '../lib/supabase';

/** The part of a PostgREST response this hook needs. */
type PgResponse = {
  data: unknown;
  error: { message: string; details?: string | null; hint?: string | null; code?: string } | null;
  count?: number | null;
};

export type ViewState<T> = {
  data: T[] | null;
  error: string | null;
  loading: boolean;
  /** Exact row count when the query asked for `{ count: 'exact' }`. */
  count: number | null;
  reload: () => void;
};

type Settled<T> = { key: string; data: T[] | null; error: string | null; count: number | null };

function describeError(error: NonNullable<PgResponse['error']>): string {
  const parts = [error.message, error.details, error.hint].filter((p): p is string => Boolean(p));
  return parts.join(' — ') || 'The request failed.';
}

/**
 * Run a read-only PostgREST query and track {data, error, loading}.
 *
 * `key` identifies the query: whenever it changes, the query re-runs. Pass
 * `null` to skip (e.g. while a dependency is still loading). `build` should
 * only read views/tables or use the whitelisted read RPC in lib/reads.ts.
 * An optional delay debounces reads; cleanup aborts and ignores stale responses.
 */
export function useView<T>(
  key: string | null,
  build: (sb: MoneyHubClient, signal: AbortSignal) => PromiseLike<PgResponse>,
  delayMs = 0,
): ViewState<T> {
  const buildRef = useRef(build);
  useEffect(() => {
    buildRef.current = build;
  });

  const [nonce, setNonce] = useState(0);
  const [settled, setSettled] = useState<Settled<T> | null>(null);
  const requestKey = key === null ? null : `${key}#${nonce}`;

  useEffect(() => {
    if (requestKey === null || !supabase) return;
    let cancelled = false;
    const controller = new AbortController();
    const client = supabase;

    const timer = setTimeout(() => { void Promise.resolve()
      .then(() => buildRef.current(client, controller.signal))
      .then(
        (res) => {
          if (cancelled) return;
          if (res.error) {
            setSettled({ key: requestKey, data: null, error: describeError(res.error), count: null });
          } else {
            const rows = Array.isArray(res.data) ? (res.data as T[]) : res.data == null ? [] : [res.data as T];
            setSettled({ key: requestKey, data: rows, error: null, count: res.count ?? null });
          }
        },
        (err: unknown) => {
          if (cancelled) return;
          const message = err instanceof Error ? err.message : 'Network error: could not reach Supabase.';
          setSettled({ key: requestKey, data: null, error: message, count: null });
        },
      ); }, delayMs);

    return () => {
      cancelled = true;
      clearTimeout(timer);
      controller.abort();
    };
  }, [requestKey, delayMs]);

  const reload = useCallback(() => setNonce((n) => n + 1), []);

  const current = settled !== null && settled.key === requestKey ? settled : null;
  return {
    data: current?.data ?? null,
    error: current?.error ?? null,
    loading: requestKey !== null && current === null,
    count: current?.count ?? null,
    reload,
  };
}
