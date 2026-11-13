import { Line, LineChart, ResponsiveContainer, CartesianGrid, XAxis, YAxis, Tooltip } from 'recharts';
import type { DebtSimulationResult } from '../types/db';
import { comparisonSeries } from '../lib/scenarios';
import { formatCurrency, formatCurrencyCompact, formatDate, formatMonth } from '../lib/format';
import { Badge, Banner, Card, CollapsibleCard, Money, Row, Stat } from './ui';
import { ChartFrame, MoneyTooltip } from './charts';
import { axisLine, axisTick, gridDash, gridStroke, lineCursor } from './chartTheme';

function Summary({ result, scenario }: { result: DebtSimulationResult; scenario?: boolean }) {
  const s = result.summary;
  return <Card title={scenario ? 'Your scenario' : 'Active-plan baseline'} tone={scenario ? 'accent' : 'default'}>
    <Stat label="Debt-free month" value={s.debt_free_month ? formatMonth(`${s.debt_free_month}-01`) : 'Not paid off'} large />
    <dl className="mt-4 divide-y divide-line">
      <Row label="Total interest"><Money value={s.total_interest} /></Row>
      <Row label="Fees"><Money value={s.total_fees} /></Row>
      <Row label="Interest saved vs minimums"><Money value={s.interest_saved_vs_minimums} /></Row>
      <Row label="Months ahead of minimums">{s.months_earlier_than_minimums ?? '—'}</Row>
    </dl>
    {!s.completed && <p className="mt-2 text-xs text-warn">Not paid off within the simulation horizon.</p>}
  </Card>;
}

export function ScenarioResults({ baseline, scenario }: { baseline: DebtSimulationResult; scenario: DebtSimulationResult }) {
  const series = comparisonSeries(baseline, scenario);
  const a = scenario.affordability;
  return <div className="min-w-0 space-y-4">
    <div className="grid gap-4 sm:grid-cols-2"><Summary result={baseline} /><Summary result={scenario} scenario /></div>
    <Card title="The path to zero" subtitle="Month-end balances · same starting debts">
      <div className="mb-3 flex flex-wrap gap-4 text-xs text-muted"><span>┄ Active-plan baseline</span><span className="text-accent-bright">━ Your scenario</span></div>
      <ChartFrame label="Baseline and scenario debt balance over time" className="h-64 sm:h-72">
        <ResponsiveContainer width="100%" height="100%"><LineChart data={series} margin={{ left: 0, right: 16, top: 12, bottom: 0 }}>
          <CartesianGrid stroke={gridStroke} strokeDasharray={gridDash} vertical={false} />
          <XAxis dataKey="month" tick={axisTick} axisLine={axisLine} tickLine={false} minTickGap={35} tickFormatter={(v: string) => formatMonth(`${v}-01`)} />
          <YAxis tick={axisTick} axisLine={false} tickLine={false} width={55} tickFormatter={(v: number) => formatCurrencyCompact(v)} />
          <Tooltip cursor={lineCursor} content={<MoneyTooltip formatLabel={(v) => formatMonth(`${String(v)}-01`)} />} />
          <Line type="monotone" dataKey="baseline" name="Active-plan baseline" stroke="var(--muted)" strokeDasharray="5 5" strokeWidth={2} dot={false} isAnimationActive={false} />
          <Line type="monotone" dataKey="scenario" name="Your scenario" stroke="var(--accent-bright)" strokeWidth={3} dot={false} isAnimationActive={false} />
        </LineChart></ResponsiveContainer>
      </ChartFrame>
      <details className="mt-3 text-xs text-muted"><summary className="min-h-10 cursor-pointer">View chart values</summary><div className="max-h-64 overflow-auto"><table className="w-full text-left"><caption className="sr-only">Monthly balance comparison</caption><thead><tr><th scope="col">Month</th><th scope="col">Baseline</th><th scope="col">Scenario</th></tr></thead><tbody>{series.map((r) => <tr key={r.month}><th scope="row" className="py-2 font-normal">{formatMonth(`${r.month}-01`)}</th><td><Money value={r.baseline} /></td><td><Money value={r.scenario} /></td></tr>)}</tbody></table></div></details>
    </Card>
    <Card title="Can your cash flow support it?" subtitle={a.through_date ? `Checked ${formatDate(a.from_date)} – ${formatDate(a.through_date)}` : 'No forecast coverage available'} tone={a.flagged_periods || a.unfunded_payoff ? 'warn' : 'default'}>
      <div className="mb-3"><Badge tone={a.status === 'within_forecast' ? 'ok' : 'warn'}>{a.status === 'unavailable' ? 'Unable to assess' : a.unfunded_payoff > 0 ? 'Unfunded what-if payoff' : a.flagged_periods > 0 ? `${a.flagged_periods} periods at risk` : 'Within the forecast buffer'}</Badge></div>
      {a.unfunded_payoff > 0 && <p className="mb-3 text-sm text-warn"><Money value={a.unfunded_payoff} /> was removed without funding. This is not an affordable-payoff confirmation.</p>}
      <p className="mb-4 text-xs leading-relaxed text-muted">Only the dates above are checked. Later months are unassessed. Monthly extras are spread across days; lump sums require existing cash. Raise and overtime income arrive on their pay dates.</p>
      {a.periods.length > 0 && <ul className="divide-y divide-line">{a.periods.map((p) => <li key={p.period_index} className="py-3">
        <div className="flex flex-wrap items-center justify-between gap-2"><h3 className="text-sm font-medium text-ink">{formatDate(p.period_start, 'short')} – {formatDate(p.period_end, 'short')}</h3><Badge tone={p.flagged ? 'warn' : 'muted'}>{p.cash_shortfall ? 'Cash shortfall' : p.flagged ? 'Buffer at risk' : 'Within buffer'}</Badge></div>
        <dl className="mt-2 grid grid-cols-2 gap-x-3 gap-y-2 text-xs sm:grid-cols-3">
          {([['Baseline obligations', p.baseline_obligations], ['Scenario extra', p.regular_extra], ['Lump-sum cash', p.lump_cash], ['Extra income', p.added_income], ['Released obligations', p.released_obligations], ['Projected cash', p.projected_cash]] as const).map(([label, value]) => <div key={label}><dt className="text-muted">{label}</dt><dd className="mt-1 text-ink"><Money value={value} /></dd></div>)}
        </dl>
        {p.flagged && <p className="mt-2 text-xs text-warn">Needs <Money value={p.gap_to_floor} /> to protect the forecast buffer{p.cash_shortfall ? <>; cash shortfall <Money value={p.cash_gap} /></> : null}.</p>}
      </li>)}</ul>}
      {a.peak_gap > 0 && <div className="mt-4 rounded-xl border border-line bg-surface-2 p-3 text-sm text-ink">
        {a.rainy_day ? <><p>Rainy-day balance: <Money value={a.rainy_day.rainy_balance} />.</p><p>Suggested total draw: <Money value={a.suggested_draw} />. Remaining gap: <Money value={a.remaining_gap} />.</p><p className="mt-1 text-xs text-muted">One shared reserve across these periods. Nothing is moved.</p></> : <p>Rainy-day coverage is unavailable. No reserve is assumed.</p>}
      </div>}
      <details className="mt-3 text-xs leading-relaxed text-muted"><summary className="min-h-10 cursor-pointer">How this check works</summary><p>{a.method}</p></details>
    </Card>
    <CollapsibleCard title="Payoff order" subtitle="Ties share a month; exact payment days may vary.">
      <div className="grid gap-6 sm:grid-cols-2">{([['Active-plan baseline', baseline], ['Your scenario', scenario]] as const).map(([label, r]) => <section key={label}><h3 className="mb-3 text-sm font-semibold text-ink">{label}</h3><ol className="space-y-3">{r.summary.payoff_order.map((p, i) => <li key={p.debt_id} className="flex items-start gap-2 text-xs"><span className="text-subtle">{i + 1}.</span><span className="flex-1 text-ink">{p.name}</span><span className="text-muted">{formatMonth(`${p.month}-01`)}</span></li>)}</ol></section>)}</div>
    </CollapsibleCard>
    <Banner tone="info" title="A scenario, not a saved plan">Your active plan stays unchanged. Estimates use blended APRs and approximate monthly interest.</Banner>
  </div>;
}
