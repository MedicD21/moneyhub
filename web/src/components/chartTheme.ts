/** Chart styling shared by every Recharts chart. Colors are CSS vars from index.css (dark only). */

/** Categorical series colors (validated palette). Fixed order, never cycled: past 8 series fall back to gray. */
const SERIES = ['--series-1', '--series-2', '--series-3', '--series-4', '--series-5', '--series-6', '--series-7', '--series-8'];
export function seriesColor(index: number): string {
  const v = SERIES[index];
  return v ? `var(${v})` : 'var(--subtle)';
}

export const axisTick = { fill: 'var(--muted)', fontSize: 11 } as const;
export const axisLine = { stroke: 'var(--chart-axis)' } as const;
export const gridStroke = 'var(--chart-grid)';
/** Dotted HUD grid. */
export const gridDash = '2 5';

const reducedMotion =
  typeof window !== 'undefined' && typeof window.matchMedia === 'function'
    ? window.matchMedia('(prefers-reduced-motion: reduce)').matches
    : false;

/**
 * Draw-in motion for series. Ease-out, short, and off entirely under reduced motion.
 * `delay` staggers series in the same chart.
 */
export function chartMotion(delay = 0) {
  return {
    isAnimationActive: !reducedMotion,
    animationDuration: 900,
    animationBegin: delay,
    animationEasing: 'ease-out' as const,
  };
}

/** Tooltip cursor for bar charts: a faint pine column. */
export const barCursor = { fill: 'var(--sweep)', stroke: 'var(--seam)', strokeDasharray: '3 3' } as const;
/** Tooltip cursor for line charts: a dashed pine rule. */
export const lineCursor = { stroke: 'var(--seam)', strokeWidth: 1, strokeDasharray: '3 3' } as const;

/** Turn React's useId (":r1:") into something safe inside url(#...). */
export function svgId(raw: string): string {
  return raw.replace(/[^a-zA-Z0-9_-]/g, '');
}
