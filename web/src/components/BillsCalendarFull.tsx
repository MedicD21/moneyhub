import { useEffect, useMemo, useRef, useState } from 'react';
import { useView } from '../hooks/useView';
import { useEntry } from './EntryContext';
import type { DailyBalanceEvent, VBillStatus, VDailyBalanceForecast, VPayPeriodForecast } from '../types/db';
import {
  addMonths,
  daysInMonth,
  formatCurrency,
  formatDate,
  formatMonth,
  monthStart,
  parseIsoDate,
  toIsoDate,
  weekdayOf,
} from '../lib/format';
import { cx } from '../lib/cx';
import { Icon } from './Icon';
import { Badge, Banner, Button, Card, Money } from './ui';
import { MonthStepper } from './MonthControls';
import { ErrorState, LoadingState } from './QueryState';
import { billStatusBadge } from './billStatus';

/**
 * Full-screen bills calendar. Every day from today to the end of the forecast horizon shows the
 * projected end-of-day SPENDABLE balance at the top right. All numbers come from views: bill rows from
 * v_bill_status and balances/scheduled items from v_daily_balance_forecast. The browser adds up nothing.
 *
 * Scheduled items only: no groceries, dining or other discretionary spending is in the balances.
 */

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MAX_CHIPS = 4;

type Visual = 'paid' | 'due' | 'overdue' | 'partial' | 'skipped';

function visualOf(b: Pick<VBillStatus, 'status' | 'overdue' | 'bill_is_active'>): Visual {
  return b.overdue && b.bill_is_active ? 'overdue' : b.status;
}

const CHIP: Record<Visual, string> = {
  paid: 'bg-ok-bg text-pos border-ok-line',
  due: 'bg-surface-2 text-ink border-line',
  overdue: 'bg-danger-bg text-danger border-danger-line',
  partial: 'bg-warn-bg text-warn border-warn-line',
  skipped: 'bg-transparent text-subtle border-line border-dashed line-through',
};

const DOT: Record<Visual, string> = {
  paid: 'bg-pos',
  due: 'bg-subtle',
  overdue: 'bg-danger',
  partial: 'bg-warn',
  skipped: 'border border-subtle bg-transparent',
};

/** Forecast items that are not already a v_bill_status row: paychecks, minimums, set-asides, plan payments, projected bills. */
function extraEvents(events: DailyBalanceEvent[]): DailyBalanceEvent[] {
  return events.filter((e) => !(e.type === 'bill' && e.occurrence_id !== null));
}

function eventLabel(e: DailyBalanceEvent): string {
  switch (e.type) {
    case 'income':
      return e.name;
    case 'debt_minimum':
      return `${e.name} (minimum)`;
    case 'set_aside':
      return `${e.name} (set-aside)`;
    case 'extra_debt':
      return e.name;
    default:
      return e.projected ? `${e.name} (projected)` : e.name;
  }
}

export function BillsCalendarFull({
  month,
  today,
  onMonth,
  onClose,
}: {
  month: string;
  today: string | null;
  onMonth: (month: string) => void;
  onClose: () => void;
}) {
  const { version } = useEntry();
  const closeRef = useRef<HTMLButtonElement>(null);
  const [selected, setSelected] = useState<string | null>(today);

  const next = addMonths(month, 1);
  const bills = useView<VBillStatus>(`cal:v_bill_status:${month}:${version}`, (sb) =>
    sb.from('v_bill_status').select('*').eq('due_month', month).order('due_date').order('bill_name'),
  );
  const balances = useView<VDailyBalanceForecast>(`cal:v_daily_balance_forecast:${month}:${version}`, (sb) =>
    sb.from('v_daily_balance_forecast').select('*').gte('day', month).lt('day', next).order('day'),
  );
  const meta = useView<VPayPeriodForecast>(`cal:v_pay_period_forecast:${version}`, (sb) =>
    sb.from('v_pay_period_forecast').select('low_balance_floor,cash_as_of').limit(1),
  );
  const floor = meta.data?.[0]?.low_balance_floor ?? null;
  const cashAsOf = meta.data?.[0]?.cash_as_of ?? null;

  useEffect(() => {
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    closeRef.current?.focus();
    return () => {
      document.body.style.overflow = overflow;
      previous?.focus?.();
    };
  }, []);

  const billsByDay = useMemo(() => {
    const m = new Map<string, VBillStatus[]>();
    for (const r of bills.data ?? []) {
      const list = m.get(r.due_date);
      if (list) list.push(r);
      else m.set(r.due_date, [r]);
    }
    return m;
  }, [bills.data]);

  const balanceByDay = useMemo(() => {
    const m = new Map<string, VDailyBalanceForecast>();
    for (const r of balances.data ?? []) m.set(r.day, r);
    return m;
  }, [balances.data]);

  const p = parseIsoDate(month);
  const inMonth = (iso: string | null): iso is string => iso !== null && iso >= month && iso < next;
  const detailDay = inMonth(selected) ? selected : null;
  const beyondHorizon = balances.data !== null && balances.data.length === 0 && today !== null && month > today;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={`Bills calendar, ${formatMonth(month)}`}
      className="fixed inset-0 z-50 flex flex-col bg-[var(--bg)]"
      onKeyDown={(e) => {
        if (e.key === 'Escape') onClose();
      }}
    >
      <header className="glass flex flex-wrap items-center justify-between gap-2 rounded-none border-x-0 border-t-0 px-3 py-2 pt-[max(0.5rem,env(safe-area-inset-top))] sm:px-5">
        <div className="flex min-w-0 items-center gap-2">
          <Icon name="calendar" size={20} className="shrink-0 text-accent-bright" />
          <h2 className="truncate text-base font-semibold tracking-tight text-ink">Bills calendar</h2>
        </div>
        <div className="flex items-center gap-2">
          {today && !inMonth(today) ? (
            <button
              type="button"
              onClick={() => {
                onMonth(monthStart(today));
                setSelected(today);
              }}
              className="min-h-10 rounded-lg px-2 text-sm font-medium text-accent hover:underline"
            >
              Today
            </button>
          ) : null}
          <MonthStepper value={month} onChange={onMonth} />
          <button
            ref={closeRef}
            type="button"
            onClick={onClose}
            aria-label="Close calendar"
            className="btn-glass grid h-10 w-10 place-items-center rounded-xl text-muted transition-colors hover:text-ink focus-visible:outline-2 focus-visible:outline-accent-bright"
          >
            <Icon name="close" size={18} />
          </button>
        </div>
      </header>

      <div className="flex-1 overflow-y-auto overscroll-contain px-2 py-3 pb-[max(1rem,env(safe-area-inset-bottom))] sm:px-4 xl:px-6">
        <div className="grid w-full gap-4 lg:grid-cols-[minmax(0,1fr)_24rem] 2xl:grid-cols-[minmax(0,1fr)_28rem]">
          <div className="min-w-0 space-y-3">
            {bills.error ? <ErrorState label="bills" message={bills.error} onRetry={bills.reload} /> : null}
            {balances.error ? (
              <Banner tone="warn" title="Projected balances didn’t load">
                {balances.error}
              </Banner>
            ) : null}
            {beyondHorizon ? (
              <Banner tone="info" title="No projection this far ahead">
                Balances only run to the end of the forecast horizon.
              </Banner>
            ) : null}

            {p && bills.data ? (
              <Grid
                month={month}
                today={today}
                selected={detailDay}
                onSelect={setSelected}
                billsByDay={billsByDay}
                balanceByDay={balanceByDay}
                floor={floor}
              />
            ) : bills.error ? null : (
              <LoadingState label="calendar" lines={10} />
            )}

            <p className="px-1 text-xs text-muted">
              Top right of each day: projected spendable balance at the end of the day.
              {cashAsOf ? ` Starts from the balance as of ${formatDate(cashAsOf, 'medium')}.` : ''} Scheduled paychecks, bills,
              minimums, set-asides and plan payments only: no groceries, dining or other spending.
            </p>
          </div>

          <div className="min-w-0 lg:sticky lg:top-0 lg:self-start">
            {detailDay ? (
              <DayDetail
                day={detailDay}
                bills={billsByDay.get(detailDay) ?? []}
                row={balanceByDay.get(detailDay) ?? null}
                floor={floor}
              />
            ) : (
              <Card title="Day details">
                <p className="text-sm text-muted">Tap a day to see its bills and projected balance.</p>
              </Card>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function balanceTone(balance: number, floor: number | null): string {
  if (balance < 0) return 'text-danger';
  if (floor !== null && balance < floor) return 'text-warn';
  return 'text-ink';
}

function Grid({
  month,
  today,
  selected,
  onSelect,
  billsByDay,
  balanceByDay,
  floor,
}: {
  month: string;
  today: string | null;
  selected: string | null;
  onSelect: (iso: string) => void;
  billsByDay: Map<string, VBillStatus[]>;
  balanceByDay: Map<string, VDailyBalanceForecast>;
  floor: number | null;
}) {
  const p = parseIsoDate(month);
  if (!p) return null;
  const lead = weekdayOf(month);
  const count = daysInMonth(p.year, p.month);
  const cells: Array<string | null> = [
    ...Array.from({ length: lead }, () => null),
    ...Array.from({ length: count }, (_, i) => toIsoDate({ year: p.year, month: p.month, day: i + 1 })),
  ];
  while (cells.length % 7 !== 0) cells.push(null);

  return (
    <div>
      <div className="grid grid-cols-7 gap-1 text-center text-[11px] xl:gap-2 xl:text-sm font-medium text-muted" aria-hidden="true">
        {WEEKDAYS.map((w) => (
          <div key={w} className="py-1">
            <span className="sm:hidden">{w.charAt(0)}</span>
            <span className="hidden sm:inline">{w}</span>
          </div>
        ))}
      </div>
      <ol className="grid grid-cols-7 gap-1 xl:gap-2" aria-label={`Calendar for ${formatMonth(month)}`}>
        {cells.map((iso, i) => {
          if (!iso) return <li key={`pad-${i}`} aria-hidden="true" className="min-h-16 sm:min-h-28 xl:min-h-36 2xl:min-h-44" />;
          const day = parseIsoDate(iso)?.day ?? 0;
          const bills = billsByDay.get(iso) ?? [];
          const row = balanceByDay.get(iso) ?? null;
          const extras = row ? extraEvents(row.events) : [];
          const isToday = iso === today;
          const isSelected = iso === selected;
          const label = [
            formatDate(iso, 'weekday'),
            row ? `projected balance ${formatCurrency(row.projected_balance)}` : null,
            bills.length > 0 ? bills.map((b) => `${b.bill_name} ${billStatusBadge(b.status, b.overdue && b.bill_is_active).label}`).join(', ') : null,
            extras.length > 0 ? extras.map(eventLabel).join(', ') : null,
          ]
            .filter(Boolean)
            .join('; ');
          const chipCount = bills.length + extras.length;
          return (
            <li key={iso} className="min-w-0">
              <button
                type="button"
                onClick={() => onSelect(iso)}
                aria-label={label}
                aria-pressed={isSelected}
                className={cx(
                  'flex min-h-16 w-full min-w-0 flex-col rounded-xl border p-1 text-left transition-colors sm:min-h-28 sm:p-1.5 xl:min-h-36 xl:p-2 2xl:min-h-44',
                  'focus-visible:outline-2 focus-visible:outline-accent-bright',
                  isSelected ? 'border-accent bg-accent-soft' : isToday ? 'nav-lit border-transparent' : 'border-line',
                  !isSelected && (chipCount > 0 ? 'bg-surface-2' : 'bg-black/20'),
                )}
              >
                <span className="flex items-start justify-between gap-1">
                  <span className={cx('text-[11px] leading-4 tabular-nums xl:text-sm', isToday ? 'font-bold text-accent-bright' : 'text-muted')}>{day}</span>
                  {row ? (
                    <span className={cx('text-[9px] leading-4 font-semibold tabular-nums sm:text-xs xl:text-sm', balanceTone(row.projected_balance, floor))}>
                      {formatCurrency(row.projected_balance)}
                    </span>
                  ) : null}
                </span>

                {chipCount > 0 ? (
                  <>
                    {/* phones: one dot per item */}
                    <span className="mt-1 flex flex-wrap gap-1 sm:hidden" aria-hidden="true">
                      {bills.map((b) => (
                        <span key={b.occurrence_id} className={cx('h-2 w-2 rounded-full', DOT[visualOf(b)])} />
                      ))}
                      {extras.map((e, k) => (
                        <span
                          key={`${e.type}-${e.name}-${k}`}
                          className={cx('h-2 w-2 rounded-full', e.type === 'income' ? 'bg-accent-bright' : 'border border-subtle bg-transparent')}
                        />
                      ))}
                    </span>
                    {/* wider: named chips */}
                    <span className="mt-1 hidden min-w-0 flex-col gap-0.5 sm:flex" aria-hidden="true">
                      {bills.slice(0, MAX_CHIPS).map((b) => (
                        <span
                          key={b.occurrence_id}
                          title={`${b.bill_name} · ${formatCurrency(b.expected_amount)}`}
                          className={cx('flex min-w-0 justify-between gap-1 rounded border px-1 text-[10.5px] leading-4 xl:text-xs xl:leading-5', CHIP[visualOf(b)])}
                        >
                          <span className="truncate">{b.bill_name}</span>
                          <span className="shrink-0 tabular-nums">{formatCurrency(b.expected_amount)}</span>
                        </span>
                      ))}
                      {extras.slice(0, Math.max(MAX_CHIPS - bills.length, 0)).map((e, k) => (
                        <span
                          key={`${e.type}-${e.name}-${k}`}
                          title={`${eventLabel(e)} · ${formatCurrency(e.amount)}`}
                          className={cx(
                            'flex min-w-0 justify-between gap-1 rounded border px-1 text-[10.5px] leading-4 xl:text-xs xl:leading-5',
                            e.type === 'income' ? 'border-ok-line bg-ok-bg text-pos' : 'border-dashed border-line text-muted',
                          )}
                        >
                          <span className="truncate">{eventLabel(e)}</span>
                          <span className="shrink-0 tabular-nums">{formatCurrency(e.amount)}</span>
                        </span>
                      ))}
                      {chipCount > MAX_CHIPS ? <span className="px-1 text-[10.5px] text-muted xl:text-xs">+{chipCount - MAX_CHIPS} more</span> : null}
                    </span>
                  </>
                ) : null}
              </button>
            </li>
          );
        })}
      </ol>
    </div>
  );
}

function DayDetail({
  day,
  bills,
  row,
  floor,
}: {
  day: string;
  bills: VBillStatus[];
  row: VDailyBalanceForecast | null;
  floor: number | null;
}) {
  const extras = row ? extraEvents(row.events) : [];
  return (
    <Card
      title={formatDate(day, 'weekday')}
      subtitle={row ? 'Projected spendable balance at the end of this day' : 'No projected balance for this day'}
      action={
        row ? (
          <span className={cx('text-lg font-semibold tracking-tight tabular-nums', balanceTone(row.projected_balance, floor))}>
            {formatCurrency(row.projected_balance)}
          </span>
        ) : undefined
      }
    >
      {bills.length === 0 && extras.length === 0 ? (
        <p className="text-sm text-muted">Nothing scheduled this day.</p>
      ) : (
        <ul className="-mx-1 divide-y divide-line">
          {bills.map((b) => {
            const overdue = b.overdue && b.bill_is_active;
            const badge = billStatusBadge(b.status, overdue);
            return (
              <li key={b.occurrence_id} className="flex items-start justify-between gap-3 px-1 py-2.5">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <span className="text-sm font-medium text-ink">{b.bill_name}</span>
                    <Badge tone={badge.tone}>{badge.label}</Badge>
                    {b.autopay ? <Badge tone="muted">Autopay</Badge> : null}
                  </div>
                  {b.paid_date ? <div className="mt-0.5 text-xs text-muted">Paid {formatDate(b.paid_date, 'short')}</div> : null}
                </div>
                <div className="shrink-0 text-right text-sm font-medium text-ink">
                  <Money value={b.status === 'paid' ? (b.paid_amount ?? b.expected_amount) : b.expected_amount} />
                </div>
              </li>
            );
          })}
          {extras.map((e, k) => (
            <li key={`${e.type}-${e.name}-${k}`} className="flex items-start justify-between gap-3 px-1 py-2.5">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-1.5">
                  <span className="text-sm font-medium text-ink">{eventLabel(e)}</span>
                  {e.type === 'income' ? <Badge tone="ok">Paycheck</Badge> : null}
                  {e.overdue ? <Badge tone="danger">Overdue</Badge> : null}
                </div>
                {e.overdue ? <div className="mt-0.5 text-xs text-muted">Was due {formatDate(e.item_date, 'short')}</div> : null}
              </div>
              <div className="shrink-0 text-right text-sm font-medium text-ink">
                <Money value={e.amount} signed showPlus />
              </div>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

/** The button that opens the calendar; lives in the Bills page header. */
export function OpenCalendarButton({ onClick }: { onClick: () => void }) {
  return (
    <Button onClick={onClick} variant="secondary" ariaLabel="Open full-screen calendar">
      <Icon name="calendar" size={16} /> Calendar
    </Button>
  );
}
