import type { CSSProperties, ReactNode } from 'react';
import type { TooltipPayloadEntry } from 'recharts';
import { formatCurrency } from '../lib/format';
import { cx } from '../lib/cx';
import { lit, shade } from './hudDefs';
import { useNearViewport } from '../hooks/useNearViewport';

/**
 * The HUD plate every chart sits on: ceramic gradient, lit top seam, corner brackets and one
 * sweep of light on arrival (styles in index.css). The inner box carries the chart's size and
 * its accessible name.
 */
export function ChartFrame({
  label,
  caption,
  className,
  style,
  children,
}: {
  label: string;
  /** optional heading row inside the plate; the plate becomes a <figure> */
  caption?: ReactNode;
  /** size classes for the chart box, e.g. "h-64 sm:h-72" */
  className?: string;
  style?: CSSProperties;
  children: ReactNode;
}) {
  const Tag = caption ? 'figure' : 'div';
  // The plate and its sized box render at once (no layout jump); the chart mounts on approach.
  const { ref, near } = useNearViewport<HTMLDivElement>();
  return (
    <Tag className={cx('hud-plate min-w-0', caption ? 'px-3 pt-3 pb-1' : 'px-1.5 pt-3 pb-1')}>
      <span className="hud-bracket" data-c="tl" aria-hidden="true" />
      <span className="hud-bracket" data-c="tr" aria-hidden="true" />
      <span className="hud-bracket" data-c="bl" aria-hidden="true" />
      <span className="hud-bracket" data-c="br" aria-hidden="true" />
      {caption ? <figcaption className="relative mb-1 px-1">{caption}</figcaption> : null}
      <div ref={ref} className={cx('relative w-full', className)} style={style} role="img" aria-label={label}>
        {near ? children : null}
      </div>
    </Tag>
  );
}

/** Tooltip body: a HUD readout with a label and one money line per series. */
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
    <div className="hud-readout min-w-40 px-3 py-2 text-xs">
      {label !== undefined ? (
        <div className="mb-1.5 border-b border-line pb-1.5 font-semibold text-ink">{formatLabel ? formatLabel(label) : String(label)}</div>
      ) : null}
      <ul className="space-y-1">
        {payload.map((p) => {
          const value = typeof p.value === 'number' ? p.value : null;
          const color = swatchColor(p);
          return (
            <li key={String(p.dataKey ?? p.name)} className="flex items-center justify-between gap-4">
              <span className="flex items-center gap-1.5 text-muted">
                <span
                  className="inline-block h-2 w-2 rounded-full"
                  style={{ background: color, boxShadow: `0 0 0 2px color-mix(in oklab, ${color} 22%, transparent)` }}
                  aria-hidden="true"
                />
                {p.name}
              </span>
              <span className="font-semibold text-ink tabular-nums">{formatCurrency(value)}</span>
            </li>
          );
        })}
      </ul>
      {extra ? <div className="mt-1.5 text-muted">{extra(row)}</div> : null}
    </div>
  );
}

/** Series entries carry the gradient url as their fill; prefer the plain stroke/color for the swatch. */
function swatchColor(p: TooltipPayloadEntry): string {
  const candidates = [p.stroke, p.color, p.fill].filter((c): c is string => typeof c === 'string' && !c.startsWith('url('));
  return candidates[0] ?? 'var(--muted)';
}

/** HTML legend placed above a chart. */
export function ChartLegend({ items }: { items: Array<{ label: string; color: string; kind?: 'bar' | 'line' }> }) {
  return (
    <ul className="mb-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted">
      {items.map((it) => (
        <li key={it.label} className="flex min-w-0 items-center gap-1.5">
          <span
            aria-hidden="true"
            className={cx('inline-block shrink-0', it.kind === 'line' ? 'h-0.5 w-4 rounded' : 'h-2.5 w-2.5 rounded-[3px]')}
            style={
              it.kind === 'line'
                ? { background: it.color, boxShadow: `0 1px 3px color-mix(in oklab, ${it.color} var(--glow-mix), transparent)` }
                : { background: `linear-gradient(90deg, ${lit(it.color, 22)}, ${it.color} 60%, ${shade(it.color, 22)})` }
            }
          />
          <span className="truncate">{it.label}</span>
        </li>
      ))}
    </ul>
  );
}
