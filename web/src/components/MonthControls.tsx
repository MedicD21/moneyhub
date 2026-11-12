import { addMonths, formatCount, formatMonth } from '../lib/format';
import { Icon } from './Icon';
import { inputClass } from './ui';
import { cx } from '../lib/cx';

/** Prev / label / next stepper over first-of-month ISO dates. */
export function MonthStepper({ value, onChange }: { value: string; onChange: (month: string) => void }) {
  return (
    <div className="inline-flex items-center rounded-lg border border-line bg-surface">
      <button
        type="button"
        onClick={() => onChange(addMonths(value, -1))}
        className="grid h-10 w-10 place-items-center rounded-l-lg text-muted hover:bg-surface-2 hover:text-ink focus-visible:outline-2 focus-visible:outline-accent"
        aria-label={`Previous month (${formatMonth(addMonths(value, -1))})`}
      >
        <Icon name="chevronLeft" size={18} />
      </button>
      <span className="min-w-32 px-2 text-center text-sm font-medium text-ink" aria-live="polite">
        {formatMonth(value)}
      </span>
      <button
        type="button"
        onClick={() => onChange(addMonths(value, 1))}
        className="grid h-10 w-10 place-items-center rounded-r-lg text-muted hover:bg-surface-2 hover:text-ink focus-visible:outline-2 focus-visible:outline-accent"
        aria-label={`Next month (${formatMonth(addMonths(value, 1))})`}
      >
        <Icon name="chevronRight" size={18} />
      </button>
    </div>
  );
}

/** A <select> over months that exist in a view, newest first. `counts` (from a view) is shown next to each month. */
export function MonthSelect({
  months,
  counts,
  value,
  onChange,
  allLabel,
  className,
  id,
}: {
  months: string[];
  counts?: ReadonlyMap<string, number>;
  value: string;
  onChange: (month: string) => void;
  allLabel?: string;
  className?: string;
  id?: string;
}) {
  return (
    <select id={id} value={value} onChange={(e) => onChange(e.target.value)} className={cx(inputClass, className)}>
      {allLabel !== undefined ? <option value="">{allLabel}</option> : null}
      {months.map((m) => (
        <option key={m} value={m}>
          {formatMonth(m)}
          {counts?.has(m) ? ` (${formatCount(counts.get(m))})` : ''}
        </option>
      ))}
    </select>
  );
}
