import { Bar, BarChart, CartesianGrid, ComposedChart, Line, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { useView } from '../hooks/useView';
import { useQueryParams } from '../hooks/useParams';
import type { VCashFlow, VMonthSpending } from '../types/db';
import { formatCount, formatCurrencyCompact, formatMonth, humanize, isMonthStart } from '../lib/format';
import { Card, Field, Money, PageHeader, Stat } from '../components/ui';
import { cx } from '../lib/cx';
import { MonthSelect } from '../components/MonthControls';
import { QueryState } from '../components/QueryState';
import { ChartLegend, MoneyTooltip } from '../components/charts';
import { axisLine, axisTick, gridStroke, seriesColor } from '../components/chartTheme';

const CHART_MONTHS = 12;

export default function Spending() {
  const { params, set } = useQueryParams();
  const cashFlow = useView<VCashFlow>('v_cash_flow', (sb) => sb.from('v_cash_flow').select('*').order('month', { ascending: false }));

  const monthParam = params.get('month');
  const latest = cashFlow.data?.[0]?.month ?? null;
  const month = isMonthStart(monthParam) ? monthParam : latest;

  const spending = useView<VMonthSpending>(month ? `v_month_spending:${month}` : null, (sb) =>
    sb
      .from('v_month_spending')
      .select('*')
      .eq('month', month ?? '')
      .order('total_out', { ascending: false })
      .order('category_name'),
  );

  const selectedFlow = cashFlow.data?.find((r) => r.month === month) ?? null;
  const months = (cashFlow.data ?? []).map((r) => r.month);
  if (month && !months.includes(month)) months.unshift(month);

  return (
    <>
      <PageHeader
        title="Spending"
        description="Transfers are excluded. Spending is net of refunds."
        actions={
          months.length > 0 ? (
            <Field label="Month" className="w-full sm:w-48">
              <MonthSelect months={months} value={month ?? ''} onChange={(m) => set({ month: m === latest ? null : m })} />
            </Field>
          ) : null
        }
      />

      <Card title="Cash flow" subtitle={`Income vs spending, last ${CHART_MONTHS} months`}>
        <QueryState state={cashFlow} label="cash flow" loadingLines={8} empty="No transactions yet, so there’s no cash flow to chart.">
          {(rows) => {
            const data = rows.slice(0, CHART_MONTHS).reverse();
            return (
              <>
                <ChartLegend
                  items={[
                    { label: 'Income', color: 'var(--income)' },
                    { label: 'Spending', color: 'var(--spending)' },
                    { label: 'Net', color: 'var(--text)', kind: 'line' },
                  ]}
                />
                <div className="h-64 w-full sm:h-72" role="img" aria-label="Bar chart of monthly income and spending with a net line">
                  <ResponsiveContainer width="100%" height="100%">
                    <ComposedChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 0 }} barGap={2}>
                      <CartesianGrid stroke={gridStroke} vertical={false} />
                      <XAxis dataKey="month" tickFormatter={(m: string) => formatMonth(m, 'short')} tick={axisTick} axisLine={axisLine} tickLine={false} minTickGap={8} />
                      <YAxis tickFormatter={formatCurrencyCompact} tick={axisTick} axisLine={false} tickLine={false} width={56} />
                      <ReferenceLine y={0} stroke="var(--chart-axis)" />
                      <Tooltip
                        cursor={{ fill: 'var(--surface-2)' }}
                        content={(p) => <MoneyTooltip active={p.active} payload={p.payload} label={p.label} formatLabel={(l) => formatMonth(String(l))} />}
                      />
                      <Bar dataKey="income" name="Income" fill="var(--income)" radius={[4, 4, 0, 0]} maxBarSize={28} />
                      <Bar dataKey="spending" name="Spending" fill="var(--spending)" radius={[4, 4, 0, 0]} maxBarSize={28} />
                      <Line dataKey="net" name="Net" stroke="var(--text)" strokeWidth={2} dot={{ r: 4, strokeWidth: 2, fill: 'var(--surface)' }} activeDot={{ r: 5 }} type="linear" />
                    </ComposedChart>
                  </ResponsiveContainer>
                </div>
              </>
            );
          }}
        </QueryState>
      </Card>

      {selectedFlow ? (
        <div className="mt-4 grid grid-cols-2 gap-4 lg:grid-cols-4">
          <Card>
            <Stat label={`Income · ${formatMonth(selectedFlow.month, 'short')}`} value={<Money value={selectedFlow.income} />} tone="pos" />
          </Card>
          <Card>
            <Stat label="Spending" value={<Money value={selectedFlow.spending} />} />
          </Card>
          <Card>
            <Stat label="Net" value={<Money value={selectedFlow.net} />} tone={selectedFlow.net < 0 ? 'danger' : 'pos'} />
          </Card>
          <Card>
            <Stat label="Uncategorized" value={formatCount(selectedFlow.uncategorized_count)} hint="transactions" />
          </Card>
        </div>
      ) : null}

      <Card className="mt-4" title={month ? `By category · ${formatMonth(month)}` : 'By category'} subtitle="Money out per category">
        {cashFlow.error ? (
          <p className="text-sm text-muted">Pick a month once cash flow loads.</p>
        ) : !month && !cashFlow.loading ? (
          <p className="text-sm text-muted">No months with transactions yet.</p>
        ) : (
          <QueryState state={spending} label="category spending" loadingLines={8} empty={`No spending recorded in ${month ? formatMonth(month) : 'this month'}.`}>
            {(rows) => <CategoryBreakdown rows={rows} />}
          </QueryState>
        )}
      </Card>
    </>
  );
}

function CategoryBreakdown({ rows }: { rows: VMonthSpending[] }) {
  const chartRows = rows.filter((r) => r.total_out > 0);
  const label = (r: VMonthSpending) => (r.category_parent ? `${r.category_parent} › ${r.category_name}` : r.category_name);
  return (
    <>
      {chartRows.length > 0 ? (
        <div className="w-full" style={{ height: chartRows.length * 34 + 32 }} role="img" aria-label="Horizontal bar chart of money out per category">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={chartRows} layout="vertical" margin={{ top: 0, right: 12, bottom: 0, left: 0 }}>
              <CartesianGrid stroke={gridStroke} horizontal={false} />
              <XAxis type="number" tickFormatter={formatCurrencyCompact} tick={axisTick} axisLine={axisLine} tickLine={false} />
              <YAxis
                type="category"
                dataKey="category_name"
                tick={axisTick}
                width={104}
                axisLine={false}
                tickLine={false}
                tickFormatter={(v: string) => (v.length > 16 ? `${v.slice(0, 15)}…` : v)}
              />
              <Tooltip
                cursor={{ fill: 'var(--surface-2)' }}
                content={(p) => (
                  <MoneyTooltip
                    active={p.active}
                    payload={p.payload}
                    label={p.label}
                    extra={(row) => `${formatCount(row.txn_count as number)} transactions`}
                  />
                )}
              />
              <Bar dataKey="total_out" name="Money out" fill={seriesColor(0)} radius={[0, 4, 4, 0]} maxBarSize={22} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      ) : (
        <p className="text-sm text-muted">No money out this month; see the table for money in.</p>
      )}

      <div className="mt-4 -mx-4 overflow-x-auto sm:-mx-5">
        <table className="w-full text-sm sm:min-w-[34rem]">
          <caption className="sr-only">Spending by category</caption>
          <thead>
            <tr className="border-y border-line text-left text-xs text-muted">
              <th scope="col" className="px-4 py-2 font-medium sm:px-5">Category</th>
              <th scope="col" className="hidden px-2 py-2 font-medium sm:table-cell">Kind</th>
              <th scope="col" className="px-2 py-2 text-right font-medium">Out</th>
              <th scope="col" className="hidden px-2 py-2 text-right font-medium sm:table-cell">In</th>
              <th scope="col" className="py-2 pr-4 pl-2 text-right font-medium sm:pr-2">Net</th>
              <th scope="col" className="hidden px-4 py-2 text-right font-medium sm:table-cell sm:px-5">Txns</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-line">
            {rows.map((r) => (
              <tr key={r.category_id ?? 'uncategorized'}>
                <th scope="row" className="px-4 py-2 text-left font-medium text-ink sm:px-5">
                  {label(r)}
                </th>
                <td className="hidden px-2 py-2 text-muted sm:table-cell">{r.category_kind ? humanize(r.category_kind) : 'Uncategorized'}</td>
                <td className="px-2 py-2 text-right text-ink">
                  <Money value={r.total_out} />
                </td>
                <td className={cx('hidden px-2 py-2 text-right sm:table-cell', r.total_in > 0 ? 'text-pos' : 'text-ink')}>
                  <Money value={r.total_in} />
                </td>
                <td className="py-2 pr-4 pl-2 text-right text-ink sm:pr-2">
                  <Money value={r.net} signed />
                </td>
                <td className="hidden px-4 py-2 text-right text-muted tabular-nums sm:table-cell sm:px-5">{formatCount(r.txn_count)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
