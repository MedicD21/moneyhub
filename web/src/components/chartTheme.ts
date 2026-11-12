/** Chart styling shared by every Recharts chart. Colors are CSS vars so light/dark switch automatically. */

/** Categorical series colors (validated palette). Fixed order, never cycled: past 8 series fall back to gray. */
const SERIES = ['--series-1', '--series-2', '--series-3', '--series-4', '--series-5', '--series-6', '--series-7', '--series-8'];
export function seriesColor(index: number): string {
  const v = SERIES[index];
  return v ? `var(${v})` : 'var(--subtle)';
}

export const axisTick = { fill: 'var(--muted)', fontSize: 11 } as const;
export const axisLine = { stroke: 'var(--chart-axis)' } as const;
export const gridStroke = 'var(--chart-grid)';
