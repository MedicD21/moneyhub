import type { BadgeTone } from './ui';

/** Status -> badge tone/label. Overdue (from the view's `overdue` column) wins over due/partial. */
export function billStatusBadge(status: string, overdue: boolean): { tone: BadgeTone; label: string } {
  if (overdue) return { tone: 'danger', label: status === 'partial' ? 'Overdue · partial' : 'Overdue' };
  switch (status) {
    case 'paid':
      return { tone: 'ok', label: 'Paid' };
    case 'partial':
      return { tone: 'warn', label: 'Partial' };
    case 'skipped':
      return { tone: 'muted', label: 'Skipped' };
    case 'projected':
      return { tone: 'muted', label: 'Projected' };
    default:
      return { tone: 'neutral', label: 'Due' };
  }
}
