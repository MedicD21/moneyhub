import { useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';

/**
 * URL search params as page state. `set` copies every other param across
 * (rather than mutating), drops empty values, and resets `page` unless it is
 * the param being set.
 */
export function useQueryParams() {
  const [params, setParams] = useSearchParams();

  const set = useCallback(
    (updates: Record<string, string | null | undefined>) => {
      setParams(
        (prev) => {
          const next = new URLSearchParams();
          prev.forEach((value, key) => {
            if (key in updates) return;
            if (key === 'page' && !('page' in updates)) return;
            next.set(key, value);
          });
          for (const [key, value] of Object.entries(updates)) {
            if (value) next.set(key, value);
          }
          return next;
        },
        { replace: true },
      );
    },
    [setParams],
  );

  return { params, set };
}
