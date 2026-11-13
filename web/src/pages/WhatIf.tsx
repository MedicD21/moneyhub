import { Link, useSearchParams } from 'react-router-dom';
import { useView } from '../hooks/useView';
import { useEntry } from '../components/EntryContext';
import { Badge, Button, PageHeader } from '../components/ui';
import { ErrorState, LoadingState } from '../components/QueryState';
import { ScenarioControls } from '../components/ScenarioControls';
import { ScenarioResults } from '../components/ScenarioResults';
import { simulateDebtPlan } from '../lib/reads';
import { decodeScenario, defaultDraft, scenarioParams, type ScenarioDraft } from '../lib/scenarios';
import type { BillRow, DebtSimulationResult, VDebt } from '../types/db';

export default function WhatIf() {
  const { version } = useEntry();
  const baseline = useView<DebtSimulationResult>(`what-if:baseline:${version}`, (sb, signal) => simulateDebtPlan(sb, {}, signal));
  const debts = useView<VDebt>(`what-if:debts:${version}`, (sb, signal) => sb.from('v_debts').select('*').eq('is_active', true).order('name').abortSignal(signal));
  const bills = useView<BillRow>(`what-if:bills:${version}`, (sb, signal) => sb.from('bills').select('*').eq('is_active', true).eq('frequency', 'monthly').is('debt_id', null).order('name').abortSignal(signal));
  const base = baseline.data?.[0];
  const failed = baseline.error ? baseline : debts.error ? debts : bills.error ? bills : null;
  return <>
    <PageHeader title="What if" description="Explore a different route to debt-free." actions={<><Badge tone="muted">Preview only</Badge><Link to="/debts" className="inline-flex min-h-10 items-center px-3 text-sm text-accent-bright underline-offset-4 hover:underline">Back to debts</Link></>} />
    {failed ? <ErrorState label="scenario inputs" message={failed.error ?? 'Request failed.'} onRetry={failed.reload} /> :
      !base || !debts.data || !bills.data ? <LoadingState label="your active plan" lines={8} /> :
      !base.monthly_balances || !base.affordability ? <ErrorState label="scenario tools" message="The scenario database update has not been installed yet." onRetry={baseline.reload} /> :
        <ScenarioEditor key={version} baseline={base} debts={debts.data} bills={bills.data} version={version} />}
  </>;
}

export function ScenarioEditor({ baseline, debts, bills, version }: { baseline: DebtSimulationResult; debts: VDebt[]; bills: BillRow[]; version: number }) {
  const [search, setSearch] = useSearchParams();
  const initial = defaultDraft(baseline);
  const decoded = decodeScenario(search.get('scenario'), initial);
  const draft = decoded.draft;
  const unchanged = JSON.stringify(draft) === JSON.stringify(initial);
  const parsed = scenarioParams(draft, baseline.defaults.start_month);
  const error = decoded.error ?? parsed.error;
  const params = parsed.params;
  const scenario = useView<DebtSimulationResult>(params && !error && !unchanged ? `what-if:${version}:${JSON.stringify(params)}` : null,
    (sb, signal) => simulateDebtPlan(sb, params ?? {}, signal), 400);
  const result = unchanged ? baseline : scenario.data?.[0];
  const reset = () => setSearch(new URLSearchParams([...search].filter(([key]) => key !== 'scenario')), { replace: true });
  const change = (next: ScenarioDraft) => {
    const query = new URLSearchParams(search); query.set('scenario', JSON.stringify(next));
    setSearch(query, { replace: true });
  };
  return <>
    <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
      <p className="text-xs text-muted">Scenario stays in this page’s URL. Bookmark the link to revisit it.</p>
      <Button onClick={reset} variant="ghost">Reset scenario</Button>
    </div>
    <div className="grid items-start gap-5 xl:grid-cols-[minmax(17rem,0.78fr)_minmax(0,1.7fr)]">
      <ScenarioControls draft={draft} onChange={change} baseline={baseline} debts={debts} bills={bills} />
      <div className="min-w-0" aria-busy={scenario.loading}>
        {error ? <div role="alert" className="rounded-2xl border border-warn-line bg-warn-bg p-4 text-sm text-warn">{error}</div> :
          scenario.error ? <ErrorState label="your scenario" message={scenario.error} onRetry={scenario.reload} /> :
            result ? <ScenarioResults baseline={baseline} scenario={result} /> : <LoadingState label="scenario comparison" lines={8} />}
      </div>
    </div>
  </>;
}
