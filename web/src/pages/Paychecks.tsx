import type { ReactNode } from 'react';
import { useView } from '../hooks/useView';
import type {
  PaycheckBillItem,
  PaycheckDebtMinimumItem,
  PaycheckExtraDebtItem,
  PaycheckIncomeItem,
  PaycheckSetAsideItem,
  VPayPeriod,
} from '../types/db';
import { formatCount, formatCurrency, formatDate, formatDateRange } from '../lib/format';
import { Badge, Money, PageHeader, Row } from '../components/ui';
import { cx } from '../lib/cx';
import { QueryState } from '../components/QueryState';
import { billStatusBadge } from '../components/billStatus';

export default function Paychecks() {
  const periods = useView<VPayPeriod>('v_pay_periods', (sb) => sb.from('v_pay_periods').select('*').order('period_offset'));

  return (
    <>
      <PageHeader title="Paychecks" description="What each paycheck has to cover, from two periods back to six ahead." />
      <QueryState
        state={periods}
        label="pay periods"
        loadingLines={10}
        empty="No pay periods. Add an active income source to plan paychecks."
      >
        {(rows) => (
          <ol className="relative space-y-4 border-l-2 border-line pl-4 sm:pl-6">
            {rows.map((p) => (
              <PeriodCard key={p.period_start} p={p} />
            ))}
          </ol>
        )}
      </QueryState>
    </>
  );
}

function PeriodCard({ p }: { p: VPayPeriod }) {
  const current = p.period_offset === 0;
  const past = p.period_offset < 0;
  const items = Array.isArray(p.items) ? p.items : [];
  const income = items.filter((i): i is PaycheckIncomeItem => i.type === 'income');
  const bills = items.filter((i): i is PaycheckBillItem => i.type === 'bill');
  const mins = items.filter((i): i is PaycheckDebtMinimumItem => i.type === 'debt_minimum');
  const sets = items.filter((i): i is PaycheckSetAsideItem => i.type === 'set_aside');
  const extra = items.filter((i): i is PaycheckExtraDebtItem => i.type === 'extra_debt');

  return (
    <li className="relative" aria-current={current ? 'step' : undefined}>
      <span
        aria-hidden="true"
        className={cx(
          'absolute top-6 -left-[23px] h-3 w-3 rounded-full border-2 sm:-left-[31px]',
          current ? 'border-accent bg-accent' : past ? 'border-line bg-surface-2' : 'border-subtle bg-surface',
        )}
      />
      <section
        className={cx(
          'rounded-2xl border bg-surface p-4 sm:p-5',
          p.shortfall ? 'border-danger-line ring-1 ring-danger-line' : current ? 'border-accent ring-1 ring-accent' : 'border-line',
          past && !current && 'opacity-85',
        )}
      >
        <header className="flex flex-wrap items-start justify-between gap-2">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-1.5">
              <h2 className="text-base font-semibold text-ink">Payday {formatDate(p.period_start, 'weekday')}</h2>
              {current ? <Badge tone="accent">Current</Badge> : past ? <Badge tone="muted">Past</Badge> : <Badge tone="neutral">Upcoming</Badge>}
              {p.shortfall ? <Badge tone="danger">Shortfall</Badge> : null}
            </div>
            <p className="mt-0.5 text-xs text-muted">
              Covers {formatDateRange(p.period_start, p.period_end)} · next payday {formatDate(p.next_pay_date, 'short')}
            </p>
          </div>
          <div className="text-right">
            <div className="text-xs text-muted">Expected net</div>
            <div className="text-lg font-semibold text-pos">
              <Money value={p.expected_net} />
            </div>
          </div>
        </header>

        <div className="mt-4 grid gap-4 md:grid-cols-2">
          <div className="space-y-4">
            {income.length > 1 ? (
              <ItemGroup title="Income">
                {income.map((i) => (
                  <ItemLine key={`${i.id}-${i.date}`} name={i.name} meta={formatDate(i.date, 'short')} amount={i.amount} />
                ))}
              </ItemGroup>
            ) : null}
            <ItemGroup title="Bills" total={p.bills_total} empty="No bills due this period.">
              {bills.map((b) => {
                const badge = billStatusBadge(b.projected ? 'projected' : b.status, b.overdue);
                return (
                  <ItemLine
                    key={`${b.id}-${b.date}`}
                    name={b.name}
                    meta={formatDate(b.date, 'short')}
                    amount={b.amount}
                    badge={badge.label !== 'Due' ? <Badge tone={badge.tone}>{badge.label}</Badge> : null}
                  />
                );
              })}
            </ItemGroup>
            <ItemGroup title="Debt minimums" total={p.minimums_total} empty="No minimums due this period.">
              {mins.map((m) => (
                <ItemLine
                  key={`${m.id}-${m.date}`}
                  name={m.name}
                  meta={`${formatDate(m.date, 'short')}${m.already_paid > 0 ? ` · ${formatCurrency(m.already_paid)} already paid` : ''}`}
                  amount={m.amount}
                />
              ))}
            </ItemGroup>
          </div>
          <div className="space-y-4">
            <ItemGroup title="Set-asides" total={p.set_asides_total} empty="No set-asides.">
              {sets.map((s) => (
                <ItemLine key={s.id} name={s.name} amount={s.amount} />
              ))}
            </ItemGroup>
            <ItemGroup title="Extra debt payment" total={p.extra_debt} empty="No active debt plan with extra payments.">
              {extra.map((x) => (
                <ItemLine
                  key={x.name}
                  name={x.name}
                  meta={`${formatCurrency(x.extra_monthly)}/mo over ${formatCount(x.paydays_per_year)} paydays a year`}
                  amount={x.amount}
                />
              ))}
            </ItemGroup>

            <div className={cx('rounded-xl border p-3', p.shortfall ? 'border-danger-line bg-danger-bg' : 'border-line bg-surface-2')}>
              <Row label="Safe to spend" strong>
                <span className={cx('text-base', p.shortfall ? 'text-danger' : 'text-ink')}>
                  <Money value={p.safe_to_spend} />
                </span>
              </Row>
              {current ? (
                <>
                  <Row label="Spent so far">
                    <Money value={p.spent_so_far} />
                  </Row>
                  <Row label="Remaining" strong>
                    <span className={cx(p.remaining_safe_to_spend < 0 ? 'text-danger' : 'text-ink')}>
                      <Money value={p.remaining_safe_to_spend} />
                    </span>
                  </Row>
                </>
              ) : null}
            </div>
          </div>
        </div>
      </section>
    </li>
  );
}

function ItemGroup({
  title,
  total,
  empty,
  children,
}: {
  title: string;
  total?: number;
  empty?: string;
  children: ReactNode[] | ReactNode;
}) {
  const list = Array.isArray(children) ? children : [children];
  const hasItems = list.some(Boolean);
  return (
    <div>
      <div className="flex items-baseline justify-between gap-2 border-b border-line pb-1">
        <h3 className="text-xs font-semibold tracking-wide text-muted uppercase">{title}</h3>
        {total !== undefined ? (
          <span className="text-sm font-semibold text-ink">
            <Money value={total} />
          </span>
        ) : null}
      </div>
      {hasItems ? <ul className="mt-1">{children}</ul> : empty ? <p className="mt-1.5 text-xs text-subtle">{empty}</p> : null}
    </div>
  );
}

function ItemLine({ name, meta, amount, badge }: { name: string; meta?: string; amount: number; badge?: ReactNode }) {
  return (
    <li className="flex items-start justify-between gap-3 py-1.5 text-sm">
      <div className="min-w-0">
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="text-ink">{name}</span>
          {badge}
        </div>
        {meta ? <div className="text-xs text-muted">{meta}</div> : null}
      </div>
      <Money value={amount} className="shrink-0 text-ink" />
    </li>
  );
}

