import { Area, AreaChart, CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { useId } from 'react';
import { useView, type ViewState } from '../hooks/useView';
import type {
  Json,
  VActiveDebtPlan,
  VDebt,
  VDebtBalanceHistory,
  VDebtPlanProjection,
  VDebtPlanSchedule,
} from '../types/db';
import {
  dayNumberToIso,
  formatCount,
  formatCurrency,
  formatCurrencyCompact,
  formatDate,
  formatMonth,
  formatPercent,
  humanize,
  isoToDayNumber,
  parseIsoDate,
} from '../lib/format';
import { Badge, Card, CollapsibleCard, Meter, Money, PageHeader, Row } from '../components/ui';
import { cx } from '../lib/cx';
import { EmptyState, ErrorState, LoadingState, QueryState } from '../components/QueryState';
import { ChartFrame, MoneyTooltip } from '../components/charts';
import { hudActiveDot, hudDefs, hudFill, hudGlow } from '../components/hudDefs';
import { axisLine, axisTick, chartMotion, gridDash, gridStroke, lineCursor, seriesColor, svgId } from '../components/chartTheme';

export default function Debts() {
  const debts = useView<VDebt>('v_debts', (sb) =>
    sb.from('v_debts').select('*').order('is_active', { ascending: false }).order('name'),
  );
  const history = useView<VDebtBalanceHistory>('v_debt_balance_history', (sb) =>
    sb.from('v_debt_balance_history').select('*').order('debt_name').order('as_of_date'),
  );
  const plan = useView<VActiveDebtPlan>('v_active_debt_plan', (sb) => sb.from('v_active_debt_plan').select('*').limit(1));
  const projection = useView<VDebtPlanProjection>('v_debt_plan_projection', (sb) =>
    sb.from('v_debt_plan_projection').select('*').order('month'),
  );
  const schedule = useView<VDebtPlanSchedule>('v_debt_plan_schedule', (sb) =>
    sb.from('v_debt_plan_schedule').select('*').order('month').order('debt_name'),
  );

  // Color follows the debt (its position in the debts list), not its rank in any one chart.
  const colorIndex = new Map<string, number>();
  (debts.data ?? []).forEach((d, i) => colorIndex.set(d.debt_id, i));
  const colorFor = (debtId: string, fallback: number) => seriesColor(colorIndex.get(debtId) ?? fallback);

  // Header counts only (no money math): how many rows each collapsed section holds.
  const debtCount = debts.data?.length ?? null;
  const historyDebtCount = history.data ? new Set(history.data.map((r) => r.debt_id)).size : null;

  return (
    <>
      <PageHeader title="Debts" description="Balances are amounts owed, as your lender shows them." />

      <CollapsibleCard
        title="Debts"
        meta={debtCount !== null ? `${formatCount(debtCount)} debt${debtCount === 1 ? '' : 's'}` : null}
      >
        <QueryState state={debts} label="debts" loadingLines={6} empty="No debts recorded.">
          {(rows) => <DebtsTable rows={rows} />}
        </QueryState>
      </CollapsibleCard>

      <CollapsibleCard
        className="mt-4"
        title="Balance history"
        subtitle="Each recorded balance, per debt"
        meta={historyDebtCount !== null ? `${formatCount(historyDebtCount)} debt${historyDebtCount === 1 ? '' : 's'}` : null}
      >
        <QueryState state={history} label="balance history" loadingLines={6} empty="No balance history yet.">
          {(rows) => <HistoryCharts rows={rows} colorFor={colorFor} />}
        </QueryState>
      </CollapsibleCard>

      <Card className="mt-4" title="Active payoff plan">
        <QueryState state={plan} label="the active debt plan" empty="No active debt plan. Ask Claude to build one and mark it active.">
          {(rows) => {
            const p = rows[0];
            if (!p) return null;
            return (
              <div className="space-y-6">
                <PlanSummary p={p} />
                <section>
                  <h3 className="mb-2 text-sm font-semibold text-ink">Projected total balance</h3>
                  <QueryState state={projection} label="the plan projection" empty="The active plan has no schedule rows.">
                    {(proj) => <ProjectionChart rows={proj} />}
                  </QueryState>
                </section>
                <section>
                  <h3 className="mb-2 text-sm font-semibold text-ink">Projected balance by debt</h3>
                  <ScheduleSection state={schedule} colorFor={colorFor} />
                </section>
              </div>
            );
          }}
        </QueryState>
      </Card>
    </>
  );
}

function DebtsTable({ rows }: { rows: VDebt[] }) {
  return (
    <>
      <DebtsList rows={rows} />
      <DebtsWideTable rows={rows} />
    </>
  );
}

/** Phones: one stacked card per debt instead of an 8-column table. */
function DebtsList({ rows }: { rows: VDebt[] }) {
  return (
    <ul className="-mx-4 divide-y divide-line border-t border-line sm:-mx-5 md:hidden">
      {rows.map((d) => {
        const promoActive = d.promo_apr !== null && d.effective_apr === d.promo_apr && d.promo_apr !== d.apr;
        return (
          <li key={d.debt_id} className={cx('px-4 py-3 sm:px-5', !d.is_active && 'opacity-75')}>
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-1.5">
                  <span className="text-sm font-medium text-ink">{d.name}</span>
                  {!d.is_active ? <Badge tone="muted">Inactive</Badge> : null}
                </div>
                <div className="mt-0.5 text-xs text-muted">{[humanize(d.kind), d.account_name].filter(Boolean).join(' · ')}</div>
              </div>
              <div className="shrink-0 text-right">
                <Money value={d.balance} className="text-base font-semibold text-ink" />
                <div className="text-[11px] text-muted">as of {formatDate(d.balance_as_of, 'short')}</div>
              </div>
            </div>
            <dl className="mt-2 grid grid-cols-3 gap-2 text-xs">
              <div className="min-w-0">
                <dt className="text-muted">APR</dt>
                <dd className="mt-0.5 text-sm text-ink tabular-nums">{formatPercent(d.effective_apr)}</dd>
              </div>
              <div className="min-w-0">
                <dt className="text-muted">Minimum</dt>
                <dd className="mt-0.5 text-sm text-ink">
                  <Money value={d.min_payment} />
                </dd>
              </div>
              <div className="min-w-0">
                <dt className="text-muted">Next due</dt>
                <dd className="mt-0.5 text-sm text-ink">{formatDate(d.next_due_date, 'short')}</dd>
              </div>
            </dl>
            {promoActive ? (
              <p className="mt-1 text-xs text-muted">
                Promo until {formatDate(d.promo_ends, 'short')}, then {formatPercent(d.apr)}
              </p>
            ) : null}
            {d.utilization_pct !== null ? (
              <div className="mt-2">
                <Utilization pct={d.utilization_pct} limit={d.credit_limit} />
              </div>
            ) : null}
            <p className="mt-1 text-[11px] text-subtle">
              Source: {d.balance_source === 'account_snapshot' ? 'Account screenshot' : d.balance_source === 'debt_balances' ? 'Debt balance' : '—'}
            </p>
          </li>
        );
      })}
    </ul>
  );
}

function DebtsWideTable({ rows }: { rows: VDebt[] }) {
  return (
    <div className="-mx-4 hidden overflow-x-auto sm:-mx-5 md:block">
      <table className="w-full min-w-[54rem] text-sm">
        <caption className="sr-only">Debts</caption>
        <thead>
          <tr className="border-y border-line text-left text-xs text-muted">
            <th scope="col" className="px-4 py-2 font-medium sm:px-5">Debt</th>
            <th scope="col" className="px-2 py-2 text-right font-medium">Balance</th>
            <th scope="col" className="px-2 py-2 font-medium">As of</th>
            <th scope="col" className="px-2 py-2 font-medium">Source</th>
            <th scope="col" className="px-2 py-2 text-right font-medium">APR</th>
            <th scope="col" className="px-2 py-2 text-right font-medium">Minimum</th>
            <th scope="col" className="px-2 py-2 font-medium">Next due</th>
            <th scope="col" className="px-4 py-2 font-medium sm:px-5">Utilization</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-line">
          {rows.map((d) => {
            const promoActive = d.promo_apr !== null && d.effective_apr === d.promo_apr && d.promo_apr !== d.apr;
            return (
              <tr key={d.debt_id} className={cx(!d.is_active && 'text-muted')}>
                <th scope="row" className="min-w-40 px-4 py-2.5 text-left font-normal sm:px-5">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <span className="font-medium text-ink">{d.name}</span>
                    {!d.is_active ? <Badge tone="muted">Inactive</Badge> : null}
                  </div>
                  <div className="text-xs text-muted">
                    {[humanize(d.kind), d.account_name].filter(Boolean).join(' · ')}
                  </div>
                </th>
                <td className="px-2 py-2.5 text-right font-semibold text-ink">
                  <Money value={d.balance} />
                </td>
                <td className="px-2 py-2.5 whitespace-nowrap text-muted">{formatDate(d.balance_as_of)}</td>
                <td className="px-2 py-2.5 whitespace-nowrap text-muted">
                  {d.balance_source === 'account_snapshot' ? 'Account screenshot' : d.balance_source === 'debt_balances' ? 'Debt balance' : '—'}
                </td>
                <td className="px-2 py-2.5 text-right whitespace-nowrap">
                  <span className="text-ink tabular-nums">{formatPercent(d.effective_apr)}</span>
                  {promoActive ? (
                    <div className="text-xs text-muted">
                      promo until {formatDate(d.promo_ends, 'short')}, then {formatPercent(d.apr)}
                    </div>
                  ) : null}
                </td>
                <td className="px-2 py-2.5 text-right text-ink">
                  <Money value={d.min_payment} />
                </td>
                <td className="px-2 py-2.5 whitespace-nowrap text-muted">{formatDate(d.next_due_date)}</td>
                <td className="px-4 py-2.5 sm:px-5">
                  {d.utilization_pct !== null ? <Utilization pct={d.utilization_pct} limit={d.credit_limit} /> : <span className="text-muted">—</span>}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function Utilization({ pct, limit }: { pct: number; limit: number | null }) {
  const tone = pct >= 90 ? 'danger' : pct >= 30 ? 'warn' : 'pos';
  return (
    <div className="min-w-32">
      <div className="flex items-baseline justify-between gap-2 text-xs">
        <span className={cx('font-medium tabular-nums', pct >= 90 ? 'text-danger' : pct >= 30 ? 'text-warn' : 'text-ink')}>{formatPercent(pct)}</span>
        {limit !== null ? <span className="text-muted">of {formatCurrency(limit)}</span> : null}
      </div>
      {/* bar width is chart scaling of the view's utilization_pct */}
      <Meter percent={pct} tone={tone} className="mt-1" />
    </div>
  );
}

type HistoryPoint = VDebtBalanceHistory & { x: number };

/** Color dot plus name, used in chart captions. */
function SeriesName({ name, color }: { name: string; color: string }) {
  return (
    <span className="flex min-w-0 items-center gap-1.5 font-medium text-ink">
      <span
        className="h-2.5 w-2.5 shrink-0 rounded-full"
        style={{ background: color, boxShadow: `0 0 0 2px color-mix(in oklab, ${color} 22%, transparent)` }}
        aria-hidden="true"
      />
      <span className="truncate">{name}</span>
    </span>
  );
}

function HistoryCharts({ rows, colorFor }: { rows: VDebtBalanceHistory[]; colorFor: (id: string, fallback: number) => string }) {
  const uid = svgId(useId());
  const groups = new Map<string, { name: string; points: HistoryPoint[] }>();
  for (const r of rows) {
    const g = groups.get(r.debt_id) ?? { name: r.debt_name, points: [] };
    g.points.push({ ...r, x: isoToDayNumber(r.as_of_date) });
    groups.set(r.debt_id, g);
  }
  const entries = [...groups.entries()];
  return (
    <div className="grid gap-4 md:grid-cols-2">
      {entries.map(([debtId, g], i) => {
        const color = colorFor(debtId, i);
        return (
          <ChartFrame
            key={debtId}
            className="h-44"
            label={`Balance history for ${g.name}`}
            caption={
              <span className="flex items-center justify-between gap-2 text-sm">
                <SeriesName name={g.name} color={color} />
                <span className="text-xs text-muted">{formatCount(g.points.length)} point{g.points.length === 1 ? '' : 's'}</span>
              </span>
            }
          >
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={g.points} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
                  <defs>{hudDefs(uid, [{ key: debtId, color, kind: 'line' }])}</defs>
                  <CartesianGrid stroke={gridStroke} strokeDasharray={gridDash} vertical={false} />
                  <XAxis
                    dataKey="x"
                    type="number"
                    scale="time"
                    domain={['dataMin', 'dataMax']}
                    tickFormatter={(x: number) => formatDate(dayNumberToIso(x), 'short')}
                    tick={axisTick}
                    axisLine={axisLine}
                    tickLine={false}
                    minTickGap={24}
                  />
                  <YAxis tickFormatter={formatCurrencyCompact} tick={axisTick} axisLine={false} tickLine={false} width={56} />
                  <Tooltip
                    cursor={lineCursor}
                    content={(p) => (
                      <MoneyTooltip
                        active={p.active}
                        payload={p.payload}
                        label={p.label}
                        formatLabel={(x) => formatDate(dayNumberToIso(Number(x)))}
                        extra={(row) => (row.source === 'account_snapshot' ? 'From account screenshot' : 'From debt balance')}
                      />
                    )}
                  />
                  <Line
                    dataKey="balance"
                    name="Balance"
                    stroke={color}
                    strokeWidth={2}
                    filter={hudGlow(uid, debtId)}
                    dot={{ r: 3.5, fill: color, stroke: 'var(--surface)', strokeWidth: 2 }}
                    activeDot={hudActiveDot(color)}
                    {...chartMotion(i * 80)}
                  />
                </LineChart>
              </ResponsiveContainer>
          </ChartFrame>
        );
      })}
    </div>
  );
}

function PlanSummary({ p }: { p: VActiveDebtPlan }) {
  return (
    <div className="grid gap-4 md:grid-cols-2">
      <div>
        <div className="flex flex-wrap items-center gap-2">
          <h3 className="text-base font-semibold text-ink">{p.name}</h3>
          <Badge tone="accent">{humanize(p.strategy)}</Badge>
        </div>
        <div className="mt-2 divide-y divide-line border-t border-line">
          <Row label="Extra each month">
            <Money value={p.extra_monthly} />
          </Row>
          <Row label="Balances as of">{formatDate(p.balances_as_of)}</Row>
          <Row label="Plan created">{formatDate(p.created_at)}</Row>
        </div>
      </div>
      <div>
        <h4 className="text-xs font-semibold tracking-wide text-muted uppercase">Summary</h4>
        <JsonFacts value={p.summary} />
        <details className="mt-3 text-sm">
          <summary className="cursor-pointer text-xs font-semibold tracking-wide text-muted uppercase">Assumptions</summary>
          <JsonFacts value={p.assumptions} />
        </details>
      </div>
    </div>
  );
}

const MONEY_KEY = /(balance|interest|payment|amount|paid|cost|saving|extra|principal|total(?!_?months?))/i;
const PERCENT_KEY = /(apr|rate|pct|percent)/i;

/** Render plan jsonb (shape is not fixed by the schema) as a readable list. */
function JsonFacts({ value }: { value: Json }) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return <p className="mt-1 text-sm text-ink">{formatJsonScalar('', value)}</p>;
  }
  const entries = Object.entries(value);
  if (entries.length === 0) return <p className="mt-1 text-sm text-muted">Nothing recorded.</p>;
  return (
    <dl className="mt-1 divide-y divide-line">
      {entries.map(([k, v]) => (
        <div key={k} className={cx('py-1.5 text-sm', formatJsonScalar(k, v).length > 40 ? 'space-y-1' : 'flex items-baseline justify-between gap-3')}>
          <dt className="shrink-0 text-muted">{humanize(k)}</dt>
          <dd className={cx('min-w-0 break-words text-ink tabular-nums', formatJsonScalar(k, v).length > 40 ? 'text-left leading-relaxed' : 'text-right')}>{formatJsonScalar(k, v)}</dd>
        </div>
      ))}
    </dl>
  );
}

function formatJsonScalar(key: string, v: Json): string {
  if (v === null) return '—';
  if (typeof v === 'boolean') return v ? 'Yes' : 'No';
  if (typeof v === 'number') {
    if (PERCENT_KEY.test(key)) return formatPercent(v);
    if (MONEY_KEY.test(key)) return formatCurrency(v);
    return formatCount(v);
  }
  if (typeof v === 'string') {
    if (/^\d{4}-\d{2}$/.test(v)) return formatMonth(`${v}-01`);
    if (/^\d{4}-\d{2}-\d{2}/.test(v) && parseIsoDate(v)) return formatDate(v);
    return v;
  }
  return JSON.stringify(v);
}

function ProjectionChart({ rows }: { rows: VDebtPlanProjection[] }) {
  const uid = svgId(useId());
  const color = seriesColor(0);
  return (
    <>
      <ChartFrame className="h-56 sm:h-64" label="Area chart of projected total debt balance by month">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={rows} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
            <defs>{hudDefs(uid, [{ key: 'total', color, kind: 'area' }])}</defs>
            <CartesianGrid stroke={gridStroke} strokeDasharray={gridDash} vertical={false} />
            <XAxis dataKey="month" tickFormatter={(m: string) => formatMonth(m, 'short')} tick={axisTick} axisLine={axisLine} tickLine={false} minTickGap={40} />
            <YAxis tickFormatter={formatCurrencyCompact} tick={axisTick} axisLine={false} tickLine={false} width={56} />
            <Tooltip
              cursor={lineCursor}
              content={(p) => (
                <MoneyTooltip
                  active={p.active}
                  payload={p.payload}
                  label={p.label}
                  formatLabel={(l) => formatMonth(String(l))}
                  extra={(row) =>
                    `Payment ${formatCurrency(row.total_payment as number | null)} · interest ${formatCurrency(row.total_interest as number | null)}`
                  }
                />
              )}
            />
            <Area
              dataKey="total_end_balance"
              name="Total balance"
              stroke={color}
              strokeWidth={2}
              fill={hudFill(uid, 'area', 'total')}
              filter={hudGlow(uid, 'total')}
              dot={rows.length <= 24 ? { r: 3, fill: color, stroke: 'var(--surface)', strokeWidth: 1.5 } : false}
              activeDot={hudActiveDot(color)}
              {...chartMotion(0)}
            />
          </AreaChart>
        </ResponsiveContainer>
      </ChartFrame>
      <details className="mt-2 text-sm">
        <summary className="cursor-pointer text-xs font-medium text-muted">Show as a table</summary>
        <div className="mt-2 -mx-4 max-h-80 overflow-auto sm:-mx-5">
          <table className="w-full text-sm sm:min-w-[28rem]">
            <thead className="sticky top-0 z-10 bg-[var(--surface-solid)]">
              <tr className="border-b border-line text-left text-xs text-muted">
                <th scope="col" className="px-4 py-2 font-medium sm:px-5">Month</th>
                <th scope="col" className="px-2 py-2 text-right font-medium">Payment</th>
                <th scope="col" className="px-2 py-2 text-right font-medium">Interest</th>
                <th scope="col" className="px-4 py-2 text-right font-medium sm:px-5">End balance</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-line">
              {rows.map((r) => (
                <tr key={r.month}>
                  <th scope="row" className="px-4 py-1.5 text-left font-normal text-ink sm:px-5">{formatMonth(r.month, 'short')}</th>
                  <td className="px-2 py-1.5 text-right"><Money value={r.total_payment} /></td>
                  <td className="px-2 py-1.5 text-right"><Money value={r.total_interest} /></td>
                  <td className="px-4 py-1.5 text-right font-medium sm:px-5"><Money value={r.total_end_balance} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>
    </>
  );
}

function ScheduleSection({
  state,
  colorFor,
}: {
  state: ViewState<VDebtPlanSchedule>;
  colorFor: (id: string, fallback: number) => string;
}) {
  const uid = svgId(useId());
  if (state.error) return <ErrorState label="the plan schedule" message={state.error} onRetry={state.reload} />;
  if (state.loading || state.data === null) return <LoadingState label="the plan schedule" />;
  if (state.data.length === 0) return <EmptyState>The active plan has no schedule rows.</EmptyState>;

  // Pivot rows (month x debt) into one object per month keyed by debt_id. Reshaping only, no arithmetic.
  const series = new Map<string, string>();
  const byMonth = new Map<string, Record<string, string | number | null>>();
  for (const r of state.data) {
    if (!series.has(r.debt_id)) series.set(r.debt_id, r.debt_name ?? 'Unknown debt');
    const row = byMonth.get(r.month) ?? { month: r.month };
    row[r.debt_id] = r.end_balance;
    byMonth.set(r.month, row);
  }
  const data = [...byMonth.values()];
  // One small chart per debt, each with its own y-scale, so a $32K auto loan can't flatten the $500 Affirm loans.
  // Earliest payoff first (ties: bigger balance first); the caption shows when each debt hits $0.
  const cards = [...series.entries()]
    .map(([id, name], i) => {
      const firstRow = data.find((r) => typeof r[id] === 'number');
      const start = (firstRow?.[id] as number | undefined) ?? 0;
      const paidOff = data.find((r) => typeof r[id] === 'number' && (r[id]) <= 0);
      return { id, name, start, color: colorFor(id, i), payoff: paidOff ? String(paidOff.month) : null };
    })
    .sort((a, b) => (a.payoff ?? '9999').localeCompare(b.payoff ?? '9999') || b.start - a.start);

  return (
    <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      {cards.map((c, i) => (
        <ChartFrame
          key={c.id}
          className="h-36"
          label={`Projected end balance for ${c.name} by month`}
          caption={
            <span className="flex items-baseline justify-between gap-2 text-sm">
              <SeriesName name={c.name} color={c.color} />
              <span className="shrink-0 text-xs text-muted">{c.payoff ? `Paid off ${formatMonth(c.payoff, 'short')}` : 'Not paid off in plan'}</span>
            </span>
          }
        >
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={data} margin={{ top: 6, right: 6, bottom: 0, left: 0 }}>
                <defs>{hudDefs(uid, [{ key: c.id, color: c.color, kind: 'area' }])}</defs>
                <CartesianGrid stroke={gridStroke} strokeDasharray={gridDash} vertical={false} />
                <XAxis dataKey="month" tickFormatter={(m: string) => formatMonth(m, 'short')} tick={axisTick} axisLine={axisLine} tickLine={false} minTickGap={40} />
                <YAxis tickFormatter={formatCurrencyCompact} tick={axisTick} axisLine={false} tickLine={false} width={48} domain={[0, 'auto']} tickCount={3} />
                <Tooltip
                  cursor={lineCursor}
                  content={(p) => <MoneyTooltip active={p.active} payload={p.payload} label={p.label} formatLabel={(l) => formatMonth(String(l))} />}
                />
                <Area
                  dataKey={c.id}
                  name={c.name}
                  stroke={c.color}
                  fill={hudFill(uid, 'area', c.id)}
                  filter={hudGlow(uid, c.id)}
                  strokeWidth={2}
                  dot={false}
                  activeDot={hudActiveDot(c.color)}
                  connectNulls
                  {...chartMotion(Math.min(i, 6) * 70)}
                />
              </AreaChart>
            </ResponsiveContainer>
        </ChartFrame>
      ))}
    </div>
  );
}
