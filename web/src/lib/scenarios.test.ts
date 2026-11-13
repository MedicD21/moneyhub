import { describe, expect, it } from 'vitest';
import { comparisonSeries, decodeScenario, defaultDraft, scenarioParams, type ScenarioDraft } from './scenarios';
import type { DebtSimulationResult } from '../types/db';

const DEBT = 'e4087555-07b4-4141-95fb-d5b7ab8db92e';

function result(over: Partial<DebtSimulationResult> = {}): DebtSimulationResult {
  return {
    schedule: [],
    summary: {
      total_interest: 0, total_fees: 0, total_interest_and_fees: 0, debt_free_month: '2027-03', completed: true,
      rollover: true, interest_saved_vs_minimums: 0, months_earlier_than_minimums: 0, what_if_removed: 0, payoff_order: [],
    },
    monthly_balances: [
      { month: '2026-12', opening_balance: 300, balance: 200, payment: 100, minimum: 100, interest: 0, fees: 0 },
      { month: '2027-01', opening_balance: 200, balance: 100, payment: 100, minimum: 100, interest: 0, fees: 0 },
    ],
    defaults: { strategy: 'avalanche', extra_monthly: 0, start_month: '2026-12', params: {} },
    affordability: {
      as_of_date: '2026-11-13', from_date: '2026-11-13', through_date: null, status: 'unavailable', periods: [],
      flagged_periods: 0, cash_shortfall_periods: 0, peak_gap: 0, unfunded_payoff: 0, rainy_day: null,
      suggested_draw: null, remaining_gap: 0, full_plan_checked: false, method: '',
    },
    ...over,
  };
}

const empty: ScenarioDraft = { extra: '', strategy: '', custom: [], lumps: [], raiseDate: '', raiseAmount: '', overtime: [], payoff: [], drops: [] };

describe('defaultDraft', () => {
  it('is empty when the active plan has no scenario inputs', () => {
    expect(defaultDraft(result())).toEqual(empty);
  });

  it('maps structured plan defaults into form fields', () => {
    const r = result({
      defaults: {
        strategy: 'custom', extra_monthly: 50, start_month: '2026-12',
        params: {
          custom: [DEBT],
          lump_sums: [{ date: '2027-02-15', amount: 500, target_debt_id: null }],
          raise: { effective_date: '2027-01-15', extra_net_per_paycheck: 50 },
          overtime: [{ pay_date: '2026-12-15', hours: 8 }],
          payoff_now: [DEBT],
          drop_payment: [{ label: 'SoFi $10 fee', from_month: '2027-01' }, { debt_id: DEBT, from_month: '2027-02' }],
        },
      },
    });
    expect(defaultDraft(r)).toEqual({
      extra: '', strategy: '', custom: [DEBT],
      lumps: [{ date: '2027-02-15', amount: '500', target: '' }],
      raiseDate: '2027-01-15', raiseAmount: '50',
      overtime: [{ date: '2026-12-15', hours: '8' }],
      payoff: [DEBT],
      drops: [{ key: 'SoFi $10 fee', kind: 'label', month: '2027-01' }, { key: DEBT, kind: 'debt', month: '2027-02' }],
    });
  });
});

describe('decodeScenario', () => {
  it('falls back without error when there is no scenario in the URL', () => {
    expect(decodeScenario(null, empty)).toEqual({ draft: empty, error: null });
  });

  it('round-trips a valid draft', () => {
    const d: ScenarioDraft = { ...empty, extra: '100', strategy: 'snowball' };
    expect(decodeScenario(JSON.stringify(d), empty)).toEqual({ draft: d, error: null });
  });

  it('rejects malformed JSON, wrong shapes, unknown strategies and oversized links', () => {
    for (const raw of ['{not json', '[]', '{"extra":1}', JSON.stringify({ ...empty, strategy: 'yolo' }), JSON.stringify({ ...empty, custom: [1] }), 'x'.repeat(16001)]) {
      const out = decodeScenario(raw, empty);
      expect(out.draft, raw.slice(0, 20)).toEqual(empty);
      expect(out.error, raw.slice(0, 20)).toMatch(/invalid/i);
    }
  });
});

describe('scenarioParams', () => {
  it('omits strategy and extra when untouched, so the active plan (with rollover) is inherited', () => {
    const { params, error } = scenarioParams(empty, '2026-12');
    expect(error).toBeNull();
    expect(params).toEqual({ lump_sums: [], payoff_now: [], drop_payment: [], overtime: [] });
    expect(params).not.toHaveProperty('extra_monthly');
    expect(params).not.toHaveProperty('strategy');
  });

  it('sends an explicit $0 extra, which disables rollover', () => {
    expect(scenarioParams({ ...empty, extra: '0' }, '2026-12').params?.extra_monthly).toBe(0);
  });

  it('converts typed money to dollars and builds every section', () => {
    const { params, error } = scenarioParams({
      ...empty, extra: '125.5', strategy: 'custom', custom: [DEBT],
      lumps: [{ date: '2027-02-15', amount: '500', target: DEBT }, { date: '2027-03-01', amount: '10.25', target: '' }],
      raiseDate: '2027-01-15', raiseAmount: '50',
      overtime: [{ date: '2026-12-15', hours: '8.5' }],
      payoff: [DEBT],
      drops: [{ key: 'SoFi $10 fee', kind: 'label', month: '2027-01' }, { key: DEBT, kind: 'debt', month: '2027-02' }],
    }, '2026-12');
    expect(error).toBeNull();
    expect(params).toEqual({
      strategy: 'custom', custom: [DEBT], extra_monthly: 125.5,
      lump_sums: [{ date: '2027-02-15', amount: 500, target_debt_id: DEBT }, { date: '2027-03-01', amount: 10.25, target_debt_id: null }],
      raise: { effective_date: '2027-01-15', extra_net_per_paycheck: 50 },
      overtime: [{ pay_date: '2026-12-15', hours: 8.5 }],
      payoff_now: [DEBT],
      drop_payment: [{ label: 'SoFi $10 fee', from_month: '2027-01' }, { debt_id: DEBT, from_month: '2027-02' }],
    });
  });

  it.each<[string, Partial<ScenarioDraft>, RegExp]>([
    ['custom strategy with no debts', { strategy: 'custom' }, /at least one debt/i],
    ['bad extra amount', { extra: 'abc' }, /valid monthly extra/i],
    ['lump sum before the start month', { lumps: [{ date: '2026-11-30', amount: '10', target: '' }] }, /on or after 2026-12/],
    ['lump sum with an impossible date', { lumps: [{ date: '2027-02-30', amount: '10', target: '' }] }, /lump-sum date/],
    ['lump sum without an amount', { lumps: [{ date: '2027-02-15', amount: '', target: '' }] }, /lump-sum amount/],
    ['raise amount without a date', { raiseAmount: '50' }, /raise date/],
    ['raise date without an amount', { raiseDate: '2027-01-15' }, /raise amount/],
    ['negative overtime hours', { overtime: [{ date: '2026-12-15', hours: '-1' }] }, /0 and 744/],
    ['blank overtime hours', { overtime: [{ date: '2026-12-15', hours: '' }] }, /0 and 744/],
    ['overtime hours over a month', { overtime: [{ date: '2026-12-15', hours: '745' }] }, /0 and 744/],
    ['stopped payment before the start month', { drops: [{ key: DEBT, kind: 'debt', month: '2026-11' }] }, /valid month/],
    ['stopped payment with a bad month', { drops: [{ key: DEBT, kind: 'debt', month: '2027-13' }] }, /valid month/],
  ])('rejects %s', (_name, patch, message) => {
    const { params, error } = scenarioParams({ ...empty, ...patch }, '2026-12');
    expect(params).toBeNull();
    expect(error).toMatch(message);
  });
});

describe('comparisonSeries', () => {
  it('joins months and shows zero after a completed payoff', () => {
    const base = result();
    const scenario = result({
      monthly_balances: [{ month: '2026-12', opening_balance: 300, balance: 0, payment: 300, minimum: 100, interest: 0, fees: 0 }],
      summary: { ...result().summary, debt_free_month: '2026-12' },
    });
    expect(comparisonSeries(base, scenario)).toEqual([
      { month: '2026-12', baseline: 200, scenario: 0 },
      { month: '2027-01', baseline: 100, scenario: 0 },
    ]);
  });

  it('leaves a gap (null) when a run did not finish', () => {
    const scenario = result({
      monthly_balances: [{ month: '2026-12', opening_balance: 300, balance: 250, payment: 50, minimum: 50, interest: 0, fees: 0 }],
      summary: { ...result().summary, debt_free_month: null, completed: false },
    });
    expect(comparisonSeries(result(), scenario)[1]).toEqual({ month: '2027-01', baseline: 100, scenario: null });
  });
});
