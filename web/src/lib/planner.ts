/**
 * Draft handling for the Planner page. Pure functions, no state, no money arithmetic.
 *
 * The user types overtime hours and a spending amount per paycheck. This file only turns what was typed
 * into the numbers sent to the database (the typed spending goes through integer cents, like every other
 * money field) and compares drafts. Every figure shown on the page, including what the hours are worth and
 * the suggested hours, is computed by public.shortfall_plan_forecast.
 */
import type { IsoDate, ShortfallPlanEntry } from '../types/db';
import { amountToInputText, centsToDollars, parseCentsAllowZero } from './money';

/** What is typed for one paycheck (text, so a half-typed "6." is fine). */
export type PlannerDraftRow = { ot: string; spend: string };
/** Draft by pay date. A missing paycheck means nothing planned. */
export type PlannerDraft = Record<IsoDate, PlannerDraftRow>;

/** Largest overtime the database accepts per paycheck. */
export const MAX_OT_HOURS = 120;

/** Keep digits and one decimal point, at most two decimals and three whole digits. */
export function sanitizeHoursInput(raw: string): string {
  const cleaned = raw.replace(/,/g, '.').replace(/[^\d.]/g, '');
  const hasDot = cleaned.includes('.');
  const [intRaw = '', ...rest] = cleaned.split('.');
  const decimals = rest.join('').slice(0, 2);
  const whole = intRaw.replace(/^0+(?=\d)/, '').slice(0, 3);
  return hasDot ? `${whole}.${decimals}` : whole;
}

/** "" -> 0, "6" -> 6, "6.5" -> 6.5; anything else (or more than 120) -> null. */
export function parseHours(text: string): number | null {
  const t = text.trim();
  if (t === '') return 0;
  if (!/^\d{0,3}\.?\d{0,2}$/.test(t) || !/\d/.test(t)) return null;
  const hours = Number(t);
  return Number.isFinite(hours) && hours <= MAX_OT_HOURS ? hours : null;
}

/** "" -> 0, "12.5" -> 12.5 (through integer cents); anything else -> null. */
export function parseSpend(text: string): number | null {
  if (text.trim() === '') return 0;
  const cents = parseCentsAllowZero(text);
  return cents === null ? null : centsToDollars(cents);
}

export type DraftEntries = { entries: ShortfallPlanEntry[]; error: string | null };

/** The draft as database entries (zero rows dropped, sorted by date), or the first thing that cannot be read. */
export function draftToEntries(draft: PlannerDraft): DraftEntries {
  const entries: ShortfallPlanEntry[] = [];
  for (const date of Object.keys(draft).sort()) {
    const row = draft[date];
    if (!row) continue;
    const ot = parseHours(row.ot);
    if (ot === null) return { entries: [], error: `Overtime hours for ${date} must be a number up to ${MAX_OT_HOURS}.` };
    const spend = parseSpend(row.spend);
    if (spend === null) return { entries: [], error: `Spending for ${date} must be an amount like 150 or 150.50.` };
    if (ot > 0 || spend > 0) entries.push({ pay_date: date, ot_hours: ot, spend });
  }
  return { entries, error: null };
}

/** Saved entries as typed text, for the form's starting state. */
export function entriesToDraft(entries: ShortfallPlanEntry[]): PlannerDraft {
  const draft: PlannerDraft = {};
  for (const e of entries) {
    draft[e.pay_date] = { ot: e.ot_hours > 0 ? String(e.ot_hours) : '', spend: e.spend > 0 ? amountToInputText(e.spend) : '' };
  }
  return draft;
}

function normalize(entries: ShortfallPlanEntry[]): string {
  return JSON.stringify(
    entries
      .filter((e) => e.ot_hours > 0 || e.spend > 0)
      .map((e) => [e.pay_date, Number(e.ot_hours), Number(e.spend)] as const)
      .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0)),
  );
}

/** True when two plans hold the same hours and spending for the same paychecks. */
export function sameEntries(a: ShortfallPlanEntry[], b: ShortfallPlanEntry[]): boolean {
  return normalize(a) === normalize(b);
}

/**
 * Hours typed plus hours suggested, kept to two decimals. These are hours, not money: what they are
 * worth is always computed by the database after the change.
 */
export function addHours(typed: string, suggested: number): string {
  const current = parseHours(typed) ?? 0;
  const total = Math.round((current + suggested) * 100) / 100;
  return total === 0 ? '' : String(total);
}
