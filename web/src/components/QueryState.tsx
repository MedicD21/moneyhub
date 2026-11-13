import type { ReactNode } from 'react';
import type { ViewState } from '../hooks/useView';
import { Icon } from './Icon';
import { Button } from './ui';
import { cx } from '../lib/cx';

export function Skeleton({ lines = 3, className }: { lines?: number; className?: string }) {
  return (
    <div className={cx('space-y-2.5', className)} aria-hidden="true">
      {Array.from({ length: lines }, (_, i) => (
        <div key={i} className={cx('skeleton-bar h-4 rounded-md', i === lines - 1 ? 'w-2/3' : 'w-full')} />
      ))}
    </div>
  );
}

export function LoadingState({ label, lines = 3 }: { label: string; lines?: number }) {
  return (
    <div role="status" aria-live="polite">
      <span className="sr-only">Loading {label}…</span>
      <Skeleton lines={lines} />
    </div>
  );
}

export function EmptyState({ children }: { children: ReactNode }) {
  return (
    <div className="rounded-2xl border border-dashed border-line-strong bg-surface-2 px-4 py-7 text-center text-sm text-muted">{children}</div>
  );
}

export function ErrorState({ label, message, onRetry }: { label: string; message: string; onRetry?: () => void }) {
  return (
    <div role="alert" className="rounded-2xl border border-danger-line bg-danger-bg px-4 py-3 text-sm backdrop-blur-md">
      <div className="flex items-start gap-2 text-danger">
        <Icon name="alert" size={18} className="mt-0.5 shrink-0" />
        <div className="min-w-0">
          <div className="font-semibold">Couldn’t load {label}</div>
          <div className="mt-0.5 break-words text-ink/80">{message}</div>
        </div>
      </div>
      {onRetry ? (
        <div className="mt-3">
          <Button onClick={onRetry} variant="secondary">
            <Icon name="refresh" size={16} /> Try again
          </Button>
        </div>
      ) : null}
    </div>
  );
}

/**
 * Renders loading / error / empty / data for one view query.
 * `label` names the data in messages, e.g. "transactions".
 */
export function QueryState<T>({
  state,
  label,
  empty,
  isEmpty = (rows) => rows.length === 0,
  loadingLines = 3,
  children,
}: {
  state: ViewState<T>;
  label: string;
  empty: ReactNode;
  isEmpty?: (rows: T[]) => boolean;
  loadingLines?: number;
  children: (rows: T[]) => ReactNode;
}) {
  if (state.error) return <ErrorState label={label} message={state.error} onRetry={state.reload} />;
  if (state.loading || state.data === null) return <LoadingState label={label} lines={loadingLines} />;
  if (isEmpty(state.data)) return <EmptyState>{empty}</EmptyState>;
  return <>{children(state.data)}</>;
}
