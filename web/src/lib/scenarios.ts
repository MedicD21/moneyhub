import type { DebtSimulationParams, DebtSimulationResult, DebtStrategy } from '../types/db';
import { centsToDollars, parseCentsAllowZero } from './money';
import { parseIsoDate } from './format';

export type ScenarioDraft = {
  extra: string;
  strategy: DebtStrategy | '';
  custom: string[];
  lumps: { date: string; amount: string; target: string }[];
  raiseDate: string;
  raiseAmount: string;
  overtime: { date: string; hours: string }[];
  payoff: string[];
  drops: { key: string; kind: 'debt' | 'label'; month: string }[];
};

export function defaultDraft(result: DebtSimulationResult): ScenarioDraft {
  const p = result.defaults.params;
  return {
    extra: '', strategy: '', custom: p.custom ?? [],
    lumps: (p.lump_sums ?? []).map((l) => ({ date: l.date, amount: String(l.amount), target: l.target_debt_id ?? '' })),
    raiseDate: p.raise?.effective_date ?? '', raiseAmount: p.raise ? String(p.raise.extra_net_per_paycheck) : '',
    overtime: (p.overtime ?? []).map((o) => ({ date: o.pay_date, hours: String(o.hours) })),
    payoff: p.payoff_now ?? [],
    drops: (p.drop_payment ?? []).map((d) => ({ key: d.label ?? d.debt_id, kind: d.label ? 'label' : 'debt', month: d.from_month })),
  };
}

const strings = (v: unknown): v is string[] => Array.isArray(v) && v.length <= 30 && v.every((x: unknown) => typeof x === 'string' && x.length <= 256);
const record = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const text = (v: unknown): v is string => typeof v === 'string' && v.length <= 256;
const rows = (v: unknown, check: (x: Record<string, unknown>) => boolean): boolean =>
  Array.isArray(v) && v.length <= 30 && v.every((x: unknown) => record(x) && check(x));
function isDraft(v: unknown): v is ScenarioDraft {
  return record(v) && text(v.extra) && ['', 'avalanche', 'snowball', 'custom', 'minimums_only'].includes(String(v.strategy)) &&
    strings(v.custom) && strings(v.payoff) && text(v.raiseDate) && text(v.raiseAmount) &&
    rows(v.lumps, (x) => text(x.date) && text(x.amount) && text(x.target)) &&
    rows(v.overtime, (x) => text(x.date) && text(x.hours)) &&
    rows(v.drops, (x) => text(x.key) && text(x.month) && (x.kind === 'debt' || x.kind === 'label'));
}

export function decodeScenario(raw: string | null, fallback: ScenarioDraft): { draft: ScenarioDraft; error: string | null } {
  if (raw === null) return { draft: fallback, error: null };
  try {
    if (raw.length > 16000) throw new Error();
    const parsed: unknown = JSON.parse(raw);
    if (!isDraft(parsed)) throw new Error();
    return { draft: parsed, error: null };
  } catch {
    return { draft: fallback, error: 'This scenario link is invalid. Reset it to start with your active plan.' };
  }
}

/** UI parsing only. All payoff and affordability math happens in PostgreSQL. */
export function scenarioParams(d: ScenarioDraft, startMonth: string): { params: DebtSimulationParams | null; error: string | null } {
  try {
    const money = (v: string, label: string): number => {
      const cents = parseCentsAllowZero(v);
      if (cents === null || cents > 10000000000) throw new Error(`Enter a valid ${label}.`);
      return centsToDollars(cents);
    };
    const date = (v: string, label: string): string => {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(v) || !parseIsoDate(v) || v < `${startMonth}-01`) throw new Error(`Choose a ${label} on or after ${startMonth}.`);
      return v;
    };
    const params: DebtSimulationParams = {
      lump_sums: d.lumps.map((l) => ({ date: date(l.date, 'lump-sum date'), amount: money(l.amount, 'lump-sum amount'), target_debt_id: l.target || null })),
      payoff_now: d.payoff,
      drop_payment: d.drops.map((p) => {
        if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(p.month) || p.month < startMonth) throw new Error('Choose a valid month for each stopped payment.');
        return p.kind === 'debt' ? { debt_id: p.key, from_month: p.month } : { label: p.key, from_month: p.month };
      }),
      overtime: d.overtime.map((o) => {
        const hours = Number(o.hours);
        if (!o.hours.trim() || !Number.isFinite(hours) || hours < 0 || hours > 744) throw new Error('Enter overtime hours between 0 and 744.');
        return { pay_date: date(o.date, 'overtime pay date'), hours };
      }),
    };
    if (d.strategy) params.strategy = d.strategy;
    if (d.strategy === 'custom') {
      if (!d.custom.length) throw new Error('Choose at least one debt for your custom order.');
      params.custom = d.custom;
    }
    if (d.extra !== '') params.extra_monthly = money(d.extra, 'monthly extra');
    if (d.raiseDate || d.raiseAmount) params.raise = { effective_date: date(d.raiseDate, 'raise date'), extra_net_per_paycheck: money(d.raiseAmount, 'raise amount') };
    return { params, error: null };
  } catch (e) {
    return { params: null, error: e instanceof Error ? e.message : 'Complete the scenario fields.' };
  }
}

/** Join server-computed totals without calculating money in the browser. */
export function comparisonSeries(base: DebtSimulationResult, scenario: DebtSimulationResult) {
  const b = new Map(base.monthly_balances.map((m) => [m.month, m.balance]));
  const s = new Map(scenario.monthly_balances.map((m) => [m.month, m.balance]));
  const months = [...new Set([...b.keys(), ...s.keys()])].sort();
  return months.map((month) => ({ month,
    baseline: b.get(month) ?? (base.summary.completed && base.summary.debt_free_month !== null && month > base.summary.debt_free_month ? 0 : null),
    scenario: s.get(month) ?? (scenario.summary.completed && scenario.summary.debt_free_month !== null && month > scenario.summary.debt_free_month ? 0 : null),
  }));
}
