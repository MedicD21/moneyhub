import { Link } from 'react-router-dom';
import { useView } from '../hooks/useView';
import type { VRainyDaySuggestion } from '../types/db';
import { formatCurrency } from '../lib/format';
import { useEntry } from './EntryContext';

/**
 * Shown only while the current pay period is short: how much of the rainy-day fund would close the gap.
 * It is a suggestion; nothing moves until you do it on the Envelopes page. Renders nothing otherwise.
 */
export function RainyDayHint() {
  const { version } = useEntry();
  const s = useView<VRainyDaySuggestion>(`v_rainy_day_suggestion:hint:${version}`, (sb) =>
    sb.from('v_rainy_day_suggestion').select('*').limit(1),
  );
  const row = s.data?.[0];
  if (!row || row.gap_to_floor <= 0) return null;
  return (
    <p className="mt-1.5 text-xs text-ink">
      {row.rainy_balance > 0 ? (
        <>
          Your rainy-day fund has {formatCurrency(row.rainy_balance)}. Suggested draw: {formatCurrency(row.suggested_draw)}
          {row.remaining_gap > 0 ? `, which still leaves a ${formatCurrency(row.remaining_gap)} gap` : ', which closes the gap'}.{' '}
        </>
      ) : (
        <>The rainy-day fund is empty, so it can’t cover this gap. </>
      )}
      <Link to="/envelopes" className="font-medium text-accent underline-offset-2 hover:underline">
        Open Envelopes
      </Link>
    </p>
  );
}
