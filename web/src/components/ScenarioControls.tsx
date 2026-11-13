import type { ReactNode } from 'react';
import type { BillRow, DebtSimulationResult, VDebt } from '../types/db';
import type { ScenarioDraft } from '../lib/scenarios';
import { Button, Card, Field, inputClass } from './ui';
import { formatCurrency } from '../lib/format';

function Group({ title, children, hint }: { title: string; children: ReactNode; hint?: string }) {
  return <details className="group border-t border-line py-4">
    <summary className="min-h-10 cursor-pointer text-sm font-semibold text-ink focus-visible:outline-2 focus-visible:outline-accent-bright">{title}</summary>
    {hint && <p className="mb-3 text-xs leading-relaxed text-muted">{hint}</p>}
    <div className="space-y-3">{children}</div>
  </details>;
}

export function ScenarioControls({ draft: d, onChange, baseline, debts, bills }: {
  draft: ScenarioDraft; onChange: (d: ScenarioDraft) => void; baseline: DebtSimulationResult; debts: VDebt[]; bills: BillRow[];
}) {
  const change = (patch: Partial<ScenarioDraft>) => onChange({ ...d, ...patch });
  const today = baseline.affordability.as_of_date;
  const month = today.slice(0, 7);
  const strategy = d.strategy || baseline.defaults.strategy;
  const amount = d.extra || String(baseline.defaults.extra_monthly);
  const options = <><option value="">Follow strategy</option>{debts.map((debt) => <option key={debt.debt_id} value={debt.debt_id}>{debt.name}</option>)}</>;
  const dropOptions = [
    ...(debts.some((debt) => debt.name.toLowerCase().startsWith('sofi')) ? [{ key: 'SoFi $10 fee', label: 'SoFi monthly fee · $10', kind: 'label' as const }] : []),
    ...bills.filter((b) => b.is_active && b.frequency === 'monthly' && !b.debt_id).map((b) => ({ key: b.name, label: `${b.name} · ${formatCurrency(b.amount)}`, kind: 'label' as const })),
    ...debts.map((debt) => ({ key: debt.debt_id, label: `Pause ${debt.name} minimum`, kind: 'debt' as const })),
  ];
  return <Card title="Shape your scenario" subtitle="Changes here never update your plan.">
    <fieldset className="mb-5">
      <legend className="mb-2 text-xs font-medium text-muted">Payoff strategy</legend>
      <div className="grid grid-cols-3 gap-1 rounded-xl border border-line bg-surface-2 p-1">
        {(['avalanche', 'snowball', 'custom'] as const).map((s) => <label key={s} className="min-w-0 cursor-pointer">
          <input className="peer sr-only" type="radio" name="strategy" value={s} checked={strategy === s} onChange={() => change({ strategy: s })} />
          <span className="flex min-h-11 items-center justify-center rounded-lg px-1 text-xs capitalize text-muted peer-checked:bg-accent-soft peer-checked:text-accent-bright peer-focus-visible:outline-2 peer-focus-visible:outline-accent-bright">{s}</span>
        </label>)}
      </div>
      <p className="mt-2 text-xs text-muted">{strategy === 'snowball' ? 'Smallest balances first.' : strategy === 'custom' ? 'Your selected order, then highest APR.' : 'Highest APR first, including Affirm.'}</p>
    </fieldset>
    <div className="space-y-3 pb-4">
      <Field label="Extra each month"><input className={inputClass} inputMode="decimal" value={d.extra} placeholder={String(baseline.defaults.extra_monthly)} onChange={(e) => change({ extra: e.target.value })} /></Field>
      <label className="block"><span className="sr-only">Extra monthly slider</span><input className="min-h-11 w-full accent-[var(--accent)]" type="range" min="0" max="2000" step="25" value={Number.isFinite(Number(amount)) ? Math.min(Number(amount), 2000) : 0} onChange={(e) => change({ extra: e.target.value })} /></label>
      <div className="flex justify-between text-xs text-subtle"><span>$0</span><span>$2,000</span></div>
      <p className="text-xs leading-relaxed text-muted">{d.extra === '' ? 'Using active-plan extra and rollover.' : Number(d.extra) === 0 ? 'Explicit $0 means minimums only; rollover is off.' : 'Added to minimums, with next-month rollover.'}</p>
      {d.extra !== '' && <Button variant="ghost" onClick={() => change({ extra: '' })}>Use active-plan extra</Button>}
    </div>
    {strategy === 'custom' && <fieldset className="border-t border-line py-4">
      <legend className="text-sm font-semibold text-ink">Custom order</legend>
      <ol className="space-y-2">{d.custom.map((id, index) => <li key={id} className="flex items-center gap-1 text-xs text-ink">
        <span className="flex-1">{index + 1}. {debts.find((debt) => debt.debt_id === id)?.name ?? id}</span>
        <Button ariaLabel={`Move ${debts.find((debt) => debt.debt_id === id)?.name ?? id} up`} disabled={index === 0} onClick={() => {
          const next = [...d.custom]; const previous = next[index - 1]; if (!previous) return;
          next[index - 1] = id; next[index] = previous; change({ custom: next });
        }}>↑</Button>
        <Button ariaLabel={`Remove debt ${index + 1} from order`} onClick={() => change({ custom: d.custom.filter((x) => x !== id) })}>×</Button>
      </li>)}</ol>
      <Field label="Add debt to order"><select className={inputClass} value="" onChange={(e) => { if (e.target.value) change({ custom: [...d.custom, e.target.value] }); }}><option value="">Choose a debt</option>{debts.filter((debt) => !d.custom.includes(debt.debt_id)).map((debt) => <option key={debt.debt_id} value={debt.debt_id}>{debt.name}</option>)}</select></Field>
    </fieldset>}
    <Group title={`Lump sums${d.lumps.length ? ` · ${d.lumps.length}` : ''}`} hint="Uses existing cash on that date. Pick a target, or follow your strategy.">
      {d.lumps.map((row, i) => <fieldset key={i} className="space-y-2 rounded-xl border border-line p-3">
        <legend className="px-1 text-xs text-muted">Lump sum {i + 1}</legend>
        <Field label={`Lump sum ${i + 1} date`}><input type="date" className={inputClass} value={row.date} onChange={(e) => change({ lumps: d.lumps.map((r, n) => n === i ? { ...r, date: e.target.value } : r) })} /></Field>
        <Field label={`Lump sum ${i + 1} amount`}><input inputMode="decimal" className={inputClass} value={row.amount} onChange={(e) => change({ lumps: d.lumps.map((r, n) => n === i ? { ...r, amount: e.target.value } : r) })} /></Field>
        <Field label={`Lump sum ${i + 1} target`}><select className={inputClass} value={row.target} onChange={(e) => change({ lumps: d.lumps.map((r, n) => n === i ? { ...r, target: e.target.value } : r) })}>{options}</select></Field>
        <Button onClick={() => change({ lumps: d.lumps.filter((_, n) => n !== i) })} ariaLabel={`Remove lump sum ${i + 1}`} variant="ghost">Remove</Button>
      </fieldset>)}
      <Button disabled={d.lumps.length >= 30} onClick={() => change({ lumps: [...d.lumps, { date: today, amount: '', target: '' }] })}>Add lump sum</Button>
    </Group>
    <Group title="Raise" hint="Extra take-home per paycheck, starting on your effective date.">
      <Field label="Raise effective date"><input type="date" className={inputClass} value={d.raiseDate} onChange={(e) => change({ raiseDate: e.target.value })} /></Field>
      <Field label="Extra net per paycheck"><input inputMode="decimal" className={inputClass} value={d.raiseAmount} onChange={(e) => change({ raiseAmount: e.target.value })} /></Field>
      {(d.raiseDate || d.raiseAmount) && <Button variant="ghost" onClick={() => change({ raiseDate: '', raiseAmount: '' })}>Remove raise</Button>}
    </Group>
    <Group title={`Overtime${d.overtime.length ? ` · ${d.overtime.length}` : ''}`} hint="Uses your configured net hourly rate. Extra income goes toward debt.">
      {d.overtime.map((row, i) => <fieldset key={i} className="space-y-2 rounded-xl border border-line p-3">
        <legend className="px-1 text-xs text-muted">Overtime {i + 1}</legend>
        <Field label={`Overtime ${i + 1} pay date`}><input type="date" className={inputClass} value={row.date} onChange={(e) => change({ overtime: d.overtime.map((r, n) => n === i ? { ...r, date: e.target.value } : r) })} /></Field>
        <Field label={`Overtime ${i + 1} hours`}><input type="number" min="0" max="744" step="0.25" className={inputClass} value={row.hours} onChange={(e) => change({ overtime: d.overtime.map((r, n) => n === i ? { ...r, hours: e.target.value } : r) })} /></Field>
        <Button onClick={() => change({ overtime: d.overtime.filter((_, n) => n !== i) })} ariaLabel={`Remove overtime ${i + 1}`} variant="ghost">Remove</Button>
      </fieldset>)}
      <Button disabled={d.overtime.length >= 30} onClick={() => change({ overtime: [...d.overtime, { date: today, hours: '' }] })}>Add overtime</Button>
    </Group>
    <Group title={`Pay off early${d.payoff.length ? ` · ${d.payoff.length}` : ''}`} hint="Starting-month lump sums fund these first. Any unfunded balance is labeled a what-if removal, not an affordable payoff.">
      {debts.map((debt) => <label key={debt.debt_id} className="flex min-h-11 cursor-pointer items-center gap-3 text-sm text-ink"><input type="checkbox" className="size-4 shrink-0 accent-[var(--accent)]" checked={d.payoff.includes(debt.debt_id)} onChange={(e) => change({ payoff: e.target.checked ? [...d.payoff, debt.debt_id] : d.payoff.filter((id) => id !== debt.debt_id) })} />{debt.name}</label>)}
    </Group>
    <Group title={`Stop payments${d.drops.length ? ` · ${d.drops.length}` : ''}`} hint="Stop a fee or redirect a bill payment. Pausing a debt minimum does not remove its balance or interest.">
      {dropOptions.map((option) => {
        const selected = d.drops.find((p) => p.key === option.key && p.kind === option.kind);
        return <div key={`${option.kind}:${option.key}`} className="border-b border-line pb-2">
          <label className="flex min-h-11 cursor-pointer items-center gap-3 text-sm text-ink"><input type="checkbox" className="size-4 shrink-0 accent-[var(--accent)]" checked={!!selected} onChange={(e) => change({ drops: e.target.checked ? [...d.drops, { key: option.key, kind: option.kind, month }] : d.drops.filter((p) => p !== selected) })} />{option.label}</label>
          {selected && <Field label={`Stop ${option.label} from`}><input type="month" className={inputClass} value={selected.month} onChange={(e) => change({ drops: d.drops.map((p) => p === selected ? { ...p, month: e.target.value } : p) })} /></Field>}
        </div>;
      })}
    </Group>
  </Card>;
}
