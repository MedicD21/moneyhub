import { Link } from 'react-router-dom';
import { useView } from '../hooks/useView';
import type { VAccountBalance, VAppInfo, VDashboard, VPayPeriodForecast, VUpcomingBill } from '../types/db';
import { addDays, formatCount, formatCurrency, formatDate, formatDateRange, formatRelativeDays, humanize } from '../lib/format';
import { Badge, Banner, Card, Money, PageHeader, Row, Stat } from '../components/ui';
import { cx } from '../lib/cx';
import { ErrorState, QueryState } from '../components/QueryState';
import { billStatusBadge } from '../components/billStatus';

export default function Dashboard() {
  const dash = useView<VDashboard>('v_dashboard', (sb) => sb.from('v_dashboard').select('*').limit(1));
  const appInfo = useView<VAppInfo>('v_app_info', (sb) => sb.from('v_app_info').select('*').limit(1));
  const forecast = useView<VPayPeriodForecast>('v_pay_period_forecast:current', (sb) =>
    sb.from('v_pay_period_forecast').select('*').eq('period_index', 1).limit(1),
  );
  const current = forecast.data?.[0] ?? null;
  const today = appInfo.data?.[0]?.today ?? null;

  // v_app_info.today is the reference date (owner's timezone); 7 days ahead is a date string, not money math.
  const cutoff = today ? addDays(today, 7) : null;
  const upcoming = useView<VUpcomingBill>(cutoff ? `v_upcoming_bills:${cutoff}` : null, (sb) =>
    sb
      .from('v_upcoming_bills')
      .select('*')
      .lte('due_date', cutoff ?? '')
      .order('due_date')
      .order('bill_name'),
  );

  const accounts = useView<VAccountBalance>('v_account_balances', (sb) =>
    sb.from('v_account_balances').select('*').eq('is_active', true).order('is_liability').order('kind').order('name'),
  );

  return (
    <>
      <PageHeader title="Dashboard" description={today ? `As of ${formatDate(today, 'weekday')}` : undefined} />

      <QueryState state={dash} label="the dashboard" empty="No dashboard data yet." loadingLines={8}>
        {(rows) => {
          const row = rows[0];
          return row ? <DashboardBody d={row} f={current} /> : null;
        }}
      </QueryState>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card
          title="Bills due in the next 7 days"
          subtitle="Unpaid bills, including any that are overdue"
          action={
            <Link to="/bills" className="text-xs font-medium text-accent underline-offset-2 hover:underline">
              All bills
            </Link>
          }
        >
          {appInfo.error ? (
            <ErrorState label="today’s date" message={appInfo.error} onRetry={appInfo.reload} />
          ) : (
            <QueryState state={upcoming} label="upcoming bills" empty="Nothing due in the next 7 days.">
              {(bills) => (
                <ul className="-my-1 divide-y divide-line">
                  {bills.map((b) => {
                    const badge = billStatusBadge(b.status, b.overdue);
                    return (
                      <li key={b.occurrence_id} className="flex items-center justify-between gap-3 py-2.5">
                        <div className="min-w-0">
                          <div className="flex flex-wrap items-center gap-1.5">
                            <span className="truncate text-sm font-medium text-ink">{b.bill_name}</span>
                            <Badge tone={badge.tone}>{badge.label}</Badge>
                            {b.autopay ? <Badge tone="muted">Autopay</Badge> : null}
                          </div>
                          <div className="mt-0.5 text-xs text-muted">
                            {formatDate(b.due_date, 'weekday')} · {formatRelativeDays(b.days_until_due)}
                          </div>
                        </div>
                        <Money value={b.remaining_amount} className="shrink-0 text-sm font-semibold" />
                      </li>
                    );
                  })}
                </ul>
              )}
            </QueryState>
          )}
        </Card>

        <Card title="Accounts" subtitle="Estimated from the last screenshot plus newer transactions">
          <QueryState state={accounts} label="accounts" empty="No active accounts yet.">
            {(list) => (
              <ul className="-my-1 divide-y divide-line">
                {list.map((a) => (
                  <li key={a.account_id} className="flex items-center justify-between gap-3 py-2.5">
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-1.5">
                        <span className="truncate text-sm font-medium text-ink">{a.name}</span>
                        {a.is_low_balance ? <Badge tone="danger">Low balance</Badge> : null}
                      </div>
                      <div className="mt-0.5 text-xs text-muted">
                        {[a.institution, humanize(a.kind), a.last4 ? `••${a.last4}` : null].filter(Boolean).join(' · ')}
                      </div>
                      <div className="mt-0.5 text-xs text-muted">
                        {a.last_snapshot_date
                          ? `Screenshot ${formatDate(a.last_snapshot_date)} · ${a.days_since_screenshot === 0 ? 'today' : `${formatCount(a.days_since_screenshot)}d old`}`
                          : 'No screenshot yet'}
                      </div>
                    </div>
                    <div className="shrink-0 text-right">
                      <Money value={a.estimated_balance_display} className={cx('text-sm font-semibold', a.is_low_balance && 'text-danger')} />
                      {a.is_liability ? <div className="text-[11px] text-muted">owed</div> : null}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </QueryState>
        </Card>
      </div>
    </>
  );
}

function DashboardBody({ d, f }: { d: VDashboard; f: VPayPeriodForecast | null }) {
  const isStale = d.oldest_data_days !== null && d.stale_after_days !== null && d.oldest_data_days >= d.stale_after_days;
  const hasPeriod = d.period_start !== null && d.safe_to_spend !== null;
  // With the forecast, a period that earlier paychecks cover is not a shortfall; only an uncovered one is.
  const shortfall = f ? f.shortfall : d.shortfall;
  // Bar width only (chart scaling): share of safe-to-spend already spent.
  const spentRatio =
    hasPeriod && d.safe_to_spend !== null && d.safe_to_spend > 0 && d.spent_so_far !== null
      ? Math.min(1, Math.max(0, d.spent_so_far / d.safe_to_spend))
      : null;

  return (
    <div className="space-y-4">
      {isStale || d.accounts_without_snapshot > 0 || shortfall || d.balance_check_issues > 0 ? (
        <div className="space-y-2">
          {shortfall ? (
            <Banner tone="danger" title="Shortfall this pay period">
              {f
                ? f.binding_balance !== null
                  ? `Even if you spend nothing extra, cash is projected to reach ${formatCurrency(f.binding_balance)} around ${formatDate(f.binding_date, 'short')}, ${formatCurrency(-f.safe_to_spend)} below your ${formatCurrency(f.low_balance_floor)} minimum balance. See Paychecks for which bills cause it.`
                  : `Even with no spending, projected cash drops below your ${formatCurrency(f.low_balance_floor)} minimum balance around ${formatDate(f.binding_date, 'short')}.`
                : `Bills, minimums and set-asides exceed this paycheck. Safe to spend is ${formatCurrency(d.safe_to_spend)}.`}
            </Banner>
          ) : null}
          {isStale ? (
            <Banner tone="warn" title={`Data is ${formatCount(d.oldest_data_days)} days old`}>
              At least one account’s latest screenshot is older than {formatCount(d.stale_after_days)} days. Balances may be off.
            </Banner>
          ) : null}
          {d.accounts_without_snapshot > 0 ? (
            <Banner tone="info" title={`${formatCount(d.accounts_without_snapshot)} account${d.accounts_without_snapshot === 1 ? '' : 's'} without a screenshot`}>
              Their balances aren’t included in the totals until a balance screenshot is imported.
            </Banner>
          ) : null}
          {d.balance_check_issues > 0 ? (
            <Banner tone="warn" title={`${formatCount(d.balance_check_issues)} balance check issue${d.balance_check_issues === 1 ? '' : 's'}`}>
              The latest screenshot doesn’t reconcile with recorded transactions for some accounts.
            </Banner>
          ) : null}
        </div>
      ) : null}

      <div className="grid gap-4 md:grid-cols-2">
        <Card title="Net position">
          <Stat label="Net (cash minus debt)" value={<Money value={d.net} />} emphasis tone={d.net < 0 ? 'danger' : 'default'} />
          <div className="mt-4 grid grid-cols-2 gap-3 border-t border-line pt-3">
            <Stat label="Cash" value={<Money value={d.total_cash} />} />
            <Stat label="Debt" value={<Money value={d.total_debt} />} />
          </div>
        </Card>

        <Card
          title="Safe to spend"
          subtitle={hasPeriod ? `This pay period · ${formatDateRange(d.period_start, d.period_end)}` : 'This pay period'}
          tone={shortfall ? 'danger' : 'accent'}
          action={
            shortfall ? <Badge tone="danger">Shortfall</Badge> : !f && d.overspent ? <Badge tone="danger">Overspent</Badge> : null
          }
        >
          {hasPeriod && f ? (
            <>
              <Stat
                label="Rest of this period"
                value={<Money value={f.safe_to_spend} />}
                emphasis
                tone={f.safe_to_spend < 0 ? 'danger' : 'default'}
                hint={
                  f.safe_to_spend < 0
                    ? 'Spending anything extra now makes the shortfall bigger'
                    : 'Steady amount that still covers short paychecks ahead'
                }
              />
              <div className="mt-3 divide-y divide-line border-t border-line">
                {f.hold_for_later > 0 ? (
                  <Row label="Held back for later paychecks">
                    <Money value={f.hold_for_later} />
                  </Row>
                ) : null}
                {f.cash_before_spending !== null ? (
                  <Row label="Cash left when this period ends">
                    <Money value={f.cash_before_spending} />
                  </Row>
                ) : null}
                {f.next_draw !== null && f.next_draw > 0 ? (
                  <Row label="Next period's bills your paycheck won't cover">
                    <Money value={f.next_draw} />
                  </Row>
                ) : null}
                <Row label="Spent so far">
                  <Money value={d.spent_so_far} />
                </Row>
                <Row label="Paycheck (expected net)">
                  <Money value={d.period_expected_net} />
                </Row>
                <Row label="Cash as of">{formatDate(f.cash_as_of, 'short')}</Row>
              </div>
            </>
          ) : hasPeriod ? (
            <>
              <Stat
                label="Remaining"
                value={<Money value={d.remaining_safe_to_spend} />}
                emphasis
                tone={d.overspent ? 'danger' : 'default'}
              />
              {spentRatio !== null ? (
                <div className="mt-3 h-2 overflow-hidden rounded-full bg-surface-2" aria-hidden="true">
                  <div className="h-full rounded-full bg-accent" style={{ width: `${spentRatio * 100}%` }} />
                </div>
              ) : null}
              <div className="mt-3 divide-y divide-line border-t border-line">
                <Row label="Safe to spend">
                  <Money value={d.safe_to_spend} />
                </Row>
                <Row label="Spent so far">
                  <Money value={d.spent_so_far} />
                </Row>
                <Row label="Paycheck (expected net)">
                  <Money value={d.period_expected_net} />
                </Row>
              </div>
            </>
          ) : (
            <p className="text-sm text-muted">No active income source covers today, so there’s no current pay period.</p>
          )}
        </Card>
      </div>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Card title="Next payday">
          {d.next_payday ? (
            <Stat label={formatDate(d.next_payday, 'weekday')} value={<Money value={d.next_payday_amount} />} tone="pos" />
          ) : (
            <p className="text-sm text-muted">None in the next 10 weeks.</p>
          )}
        </Card>
        <Card title="Due in 7 days">
          <Stat label={`${formatCount(d.bills_due_7d_count)} bill${d.bills_due_7d_count === 1 ? '' : 's'}`} value={<Money value={d.bills_due_7d_total} />} />
        </Card>
        <Card title="Overdue" tone={d.overdue_bills_count > 0 ? 'danger' : 'default'}>
          <Stat
            label={`${formatCount(d.overdue_bills_count)} bill${d.overdue_bills_count === 1 ? '' : 's'}`}
            value={<Money value={d.overdue_bills_total} />}
            tone={d.overdue_bills_count > 0 ? 'danger' : 'default'}
          />
        </Card>
        <Card title="Needs attention">
          <ul className="space-y-1 text-sm">
            <li className="flex justify-between gap-2">
              <Link to="/transactions?review=1" className="text-muted underline-offset-2 hover:text-ink hover:underline">
                To review
              </Link>
              <span className={cx('font-semibold tabular-nums', d.review_queue_count > 0 ? 'text-warn' : 'text-ink')}>
                {formatCount(d.review_queue_count)}
              </span>
            </li>
            <li className="flex justify-between gap-2">
              <span className="text-muted">Balance checks</span>
              <span className={cx('font-semibold tabular-nums', d.balance_check_issues > 0 ? 'text-warn' : 'text-ink')}>
                {formatCount(d.balance_check_issues)}
              </span>
            </li>
            <li className="flex justify-between gap-2">
              <span className="text-muted">Low balances</span>
              <span className={cx('font-semibold tabular-nums', d.low_balance_accounts > 0 ? 'text-danger' : 'text-ink')}>
                {formatCount(d.low_balance_accounts)}
              </span>
            </li>
          </ul>
        </Card>
      </div>
    </div>
  );
}
