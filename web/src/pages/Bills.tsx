import { useView } from '../hooks/useView';
import { useQueryParams } from '../hooks/useParams';
import type { VBillStatus, VMonthlyBillsTotal } from '../types/db';
import {
  daysInMonth,
  formatCount,
  formatCurrencyWhole,
  formatDate,
  formatMonth,
  formatRelativeDays,
  humanize,
  isMonthStart,
  monthStart,
  parseIsoDate,
  todayLocal,
  toIsoDate,
  weekdayOf,
} from '../lib/format';
import { Badge, Card, Money, PageHeader, Row } from '../components/ui';
import { cx } from '../lib/cx';
import { MonthStepper } from '../components/MonthControls';
import { QueryState } from '../components/QueryState';
import { billStatusBadge } from '../components/billStatus';

type Visual = 'paid' | 'due' | 'overdue' | 'partial' | 'skipped';

function visualOf(b: Pick<VBillStatus, 'status' | 'overdue'>): Visual {
  if (b.overdue) return 'overdue';
  return b.status;
}

const CHIP: Record<Visual, string> = {
  paid: 'bg-ok-bg text-pos border-ok-line',
  due: 'bg-surface-2 text-ink border-line',
  overdue: 'bg-danger-bg text-danger border-danger-line',
  partial: 'bg-warn-bg text-warn border-warn-line',
  skipped: 'bg-surface text-subtle border-line border-dashed line-through',
};

const DOT: Record<Visual, string> = {
  paid: 'bg-pos',
  due: 'bg-subtle',
  overdue: 'bg-danger',
  partial: 'bg-warn',
  skipped: 'border border-subtle bg-transparent',
};

const LEGEND: Array<[Visual, string]> = [
  ['paid', 'Paid'],
  ['due', 'Due'],
  ['overdue', 'Overdue'],
  ['partial', 'Partial'],
  ['skipped', 'Skipped'],
];

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export default function Bills() {
  const { params, set } = useQueryParams();
  const today = todayLocal();
  const monthParam = params.get('month');
  const month = isMonthStart(monthParam) ? monthParam : monthStart(today);

  const bills = useView<VBillStatus>(`v_bill_status:${month}`, (sb) =>
    sb.from('v_bill_status').select('*').eq('due_month', month).order('due_date').order('bill_name'),
  );
  const totals = useView<VMonthlyBillsTotal>('v_monthly_bills_total', (sb) => sb.from('v_monthly_bills_total').select('*').limit(1));

  return (
    <>
      <PageHeader
        title="Bills"
        actions={<MonthStepper value={month} onChange={(m) => set({ month: m === monthStart(today) ? null : m })} />}
      />

      <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_18rem]">
        <Card title={formatMonth(month)} subtitle="Bill due dates, colored by status">
          <QueryState state={bills} label="bills" loadingLines={8} empty={`No bills due in ${formatMonth(month)}.`} isEmpty={() => false}>
            {(rows) => <Calendar month={month} today={today} rows={rows} />}
          </QueryState>
          <ul className="mt-3 flex flex-wrap gap-x-4 gap-y-1.5 text-xs text-muted" aria-label="Legend">
            {LEGEND.map(([v, label]) => (
              <li key={v} className="flex items-center gap-1.5">
                <span className={cx('inline-block h-2.5 w-2.5 rounded-full', DOT[v])} aria-hidden="true" />
                {label}
              </li>
            ))}
          </ul>
        </Card>

        <Card title="Typical month" subtitle="All active bills, normalized to a monthly amount">
          <QueryState state={totals} label="the monthly bills total" empty="No active bills yet.">
            {(rows) => {
              const t = rows[0];
              if (!t) return null;
              return (
                <>
                  <div className="text-3xl font-semibold tracking-tight text-ink">
                    <Money value={t.monthly_total} />
                  </div>
                  <div className="mt-3 divide-y divide-line border-t border-line">
                    <Row label="On autopay">
                      <Money value={t.autopay_monthly_total} />
                    </Row>
                    <Row label="Variable amount">
                      <Money value={t.variable_monthly_total} />
                    </Row>
                    <Row label="Active bills">{formatCount(t.active_bill_count)}</Row>
                  </div>
                </>
              );
            }}
          </QueryState>
        </Card>
      </div>

      <Card title={`Bills in ${formatMonth(month)}`} className="mt-4">
        <QueryState state={bills} label="bills" loadingLines={6} empty={`No bills due in ${formatMonth(month)}.`}>
          {(rows) => (
            <ul className="-mx-4 divide-y divide-line sm:-mx-5">
              {rows.map((b) => (
                <BillRow key={b.occurrence_id} b={b} />
              ))}
            </ul>
          )}
        </QueryState>
      </Card>
    </>
  );
}

function Calendar({ month, today, rows }: { month: string; today: string; rows: VBillStatus[] }) {
  const p = parseIsoDate(month);
  if (!p) return null;
  const lead = weekdayOf(month);
  const count = daysInMonth(p.year, p.month);

  const byDate = new Map<string, VBillStatus[]>();
  for (const r of rows) {
    const list = byDate.get(r.due_date);
    if (list) list.push(r);
    else byDate.set(r.due_date, [r]);
  }

  const cells: Array<string | null> = [
    ...Array.from({ length: lead }, () => null),
    ...Array.from({ length: count }, (_, i) => toIsoDate({ year: p.year, month: p.month, day: i + 1 })),
  ];
  while (cells.length % 7 !== 0) cells.push(null);

  return (
    <div>
      <div className="grid grid-cols-7 gap-1 text-center text-[11px] font-medium text-muted" aria-hidden="true">
        {WEEKDAYS.map((w) => (
          <div key={w} className="py-1">
            <span className="sm:hidden">{w.charAt(0)}</span>
            <span className="hidden sm:inline">{w}</span>
          </div>
        ))}
      </div>
      <ol className="grid grid-cols-7 gap-1" aria-label={`Calendar for ${formatMonth(month)}`}>
        {cells.map((iso, i) => {
          if (!iso) return <li key={`pad-${i}`} aria-hidden="true" className="min-h-14 sm:min-h-20" />;
          const day = parseIsoDate(iso)?.day ?? 0;
          const items = byDate.get(iso) ?? [];
          const isToday = iso === today;
          const label =
            items.length === 0
              ? formatDate(iso, 'weekday')
              : `${formatDate(iso, 'weekday')}: ${items.map((b) => `${b.bill_name} ${billStatusBadge(b.status, b.overdue).label}`).join(', ')}`;
          return (
            <li
              key={iso}
              aria-label={label}
              className={cx(
                'min-h-14 min-w-0 rounded-lg border p-1 sm:min-h-20 sm:p-1.5',
                isToday ? 'border-accent' : 'border-line',
                items.length > 0 ? 'bg-surface' : 'bg-bg',
              )}
            >
              <div className={cx('text-[11px] leading-4 tabular-nums', isToday ? 'font-bold text-accent' : 'text-muted')}>{day}</div>
              {items.length > 0 ? (
                <>
                  {/* phones: one dot per bill */}
                  <div className="mt-1 flex flex-wrap gap-1 sm:hidden" aria-hidden="true">
                    {items.map((b) => (
                      <span key={b.occurrence_id} className={cx('h-2 w-2 rounded-full', DOT[visualOf(b)])} />
                    ))}
                  </div>
                  {/* wider: named chips */}
                  <ul className="mt-1 hidden space-y-0.5 sm:block" aria-hidden="true">
                    {items.map((b) => (
                      <li
                        key={b.occurrence_id}
                        title={`${b.bill_name} · ${formatCurrencyWhole(b.expected_amount)} · ${billStatusBadge(b.status, b.overdue).label}`}
                        className={cx('truncate rounded border px-1 text-[10.5px] leading-4', CHIP[visualOf(b)])}
                      >
                        {b.bill_name}
                      </li>
                    ))}
                  </ul>
                </>
              ) : null}
            </li>
          );
        })}
      </ol>
    </div>
  );
}

function BillRow({ b }: { b: VBillStatus }) {
  const badge = billStatusBadge(b.status, b.overdue);
  const unpaid = b.status === 'due' || b.status === 'partial';
  return (
    <li className="px-4 py-3 sm:px-5">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="text-sm font-medium text-ink">{b.bill_name}</span>
            <Badge tone={badge.tone}>{badge.label}</Badge>
            {b.autopay ? <Badge tone="muted">Autopay</Badge> : null}
            {b.is_variable ? <Badge tone="muted">Variable</Badge> : null}
          </div>
          <div className="mt-0.5 text-xs text-muted">
            Due {formatDate(b.due_date, 'weekday')}
            {unpaid ? ` · ${formatRelativeDays(b.days_until_due)}` : ''}
            {b.paid_date ? ` · paid ${formatDate(b.paid_date, 'short')}` : ''}
          </div>
          <div className="mt-0.5 text-xs text-muted">
            {[humanize(b.frequency), b.category_name, b.pay_from_account_name ? `from ${b.pay_from_account_name}` : null]
              .filter(Boolean)
              .join(' · ')}
          </div>
        </div>
        <dl className="grid shrink-0 grid-cols-3 gap-3 text-right text-xs sm:w-72">
          <div>
            <dt className="text-muted">Expected</dt>
            <dd className="mt-0.5 text-sm font-medium text-ink">
              <Money value={b.expected_amount} />
            </dd>
          </div>
          <div>
            <dt className="text-muted">Paid</dt>
            <dd className="mt-0.5 text-sm font-medium text-ink">
              <Money value={b.paid_amount} />
            </dd>
          </div>
          <div>
            <dt className="text-muted">Remaining</dt>
            <dd className={cx('mt-0.5 text-sm font-semibold', b.overdue ? 'text-danger' : 'text-ink')}>
              <Money value={b.remaining_amount} />
            </dd>
          </div>
        </dl>
      </div>
    </li>
  );
}
