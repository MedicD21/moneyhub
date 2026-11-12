import type { ReactNode } from 'react';
import type { TooltipPayloadEntry } from 'recharts';
import { formatCurrency } from '../lib/format';
import { cx } from '../lib/cx';

/** Tooltip body: label plus one money line per series. */
export function MoneyTooltip({
  active,
  payload,
  label,
  formatLabel,
  extra,
}: {
  active?: boolean;
  payload?: ReadonlyArray<TooltipPayloadEntry>;
  label?: string | number;
  formatLabel?: (label: string | number) => string;
  extra?: (row: Record<string, unknown>) => ReactNode;
}) {
  if (!active || !payload || payload.length === 0) return null;
  const row = (payload[0]?.payload ?? {}) as Record<string, unknown>;
  return (
    <div className="rounded-lg border border-line bg-surface px-3 py-2 text-xs shadow-lg">
      {label !== undefined ? <div className="mb-1 font-semibold text-ink">{formatLabel ? formatLabel(label) : String(label)}</div> : null}
      <ul className="space-y-0.5">
        {payload.map((p) => {
          const value = typeof p.value === 'number' ? p.value : null;
          return (
            <li key={String(p.dataKey ?? p.name)} className="flex items-center justify-between gap-4">
              <span className="flex items-center gap-1.5 text-muted">
                <span className="inline-block h-2 w-2 rounded-full" style={{ background: p.color ?? p.stroke ?? p.fill }} aria-hidden="true" />
                {p.name}
              </span>
              <span className="font-medium text-ink tabular-nums">{formatCurrency(value)}</span>
            </li>
          );
        })}
      </ul>
      {extra ? <div className="mt-1 text-muted">{extra(row)}</div> : null}
    </div>
  );
}

/** HTML legend placed above a chart. */
export function ChartLegend({ items }: { items: Array<{ label: string; color: string; kind?: 'bar' | 'line' }> }) {
  return (
    <ul className="mb-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted">
      {items.map((it) => (
        <li key={it.label} className="flex min-w-0 items-center gap-1.5">
          <span
            aria-hidden="true"
            className={cx('inline-block shrink-0', it.kind === 'line' ? 'h-0.5 w-4 rounded' : 'h-2.5 w-2.5 rounded-sm')}
            style={{ background: it.color }}
          />
          <span className="truncate">{it.label}</span>
        </li>
      ))}
    </ul>
  );
}
