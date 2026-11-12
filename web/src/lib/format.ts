/**
 * Formatting helpers. Display only: nothing here adds up money.
 *
 * Dates from Postgres are 'YYYY-MM-DD' strings. `new Date('2026-03-05')` parses
 * that as UTC midnight, which shows as Mar 4 west of Greenwich, so these
 * helpers parse the parts by hand and format in UTC to avoid any shift.
 */

const usd = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });
const usdWhole = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
  maximumFractionDigits: 0,
});
const usdCompact = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
  notation: 'compact',
  maximumFractionDigits: 1,
});
const plainNumber = new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 });

export const EMPTY = '—';

/** $1,234.56 / -$1,234.56. null/undefined/NaN render as an em dash. */
export function formatCurrency(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return EMPTY;
  // Avoid "-$0.00" for negative zero.
  return usd.format(Object.is(value, -0) ? 0 : value);
}

/** Whole dollars, for tight spaces such as calendar cells. */
export function formatCurrencyWhole(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return EMPTY;
  return usdWhole.format(Object.is(value, -0) ? 0 : value);
}

/** $1.2K, for chart axes. */
export function formatCurrencyCompact(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return EMPTY;
  return usdCompact.format(value);
}

/** Positive -> 'in', negative -> 'out', zero/null -> 'zero'. Used to pick a color. */
export type MoneyTone = 'in' | 'out' | 'zero';
export function moneyTone(value: number | null | undefined): MoneyTone {
  if (value === null || value === undefined || value === 0 || Number.isNaN(value)) return 'zero';
  return value > 0 ? 'in' : 'out';
}

/** 24.99 -> "24.99%". The value is already a percentage. */
export function formatPercent(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return EMPTY;
  return `${plainNumber.format(value)}%`;
}

export function formatCount(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return EMPTY;
  return plainNumber.format(value);
}

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------

export type DateParts = { year: number; month: number; day: number };

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})/;

/** Parse 'YYYY-MM-DD' (or the date prefix of a timestamp) without any timezone handling. */
export function parseIsoDate(iso: string): DateParts | null {
  const m = ISO_DATE.exec(iso);
  if (!m) return null;
  const year = Number(m[1]);
  const month = Number(m[2]);
  const day = Number(m[3]);
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) return null;
  return { year, month, day };
}

function pad2(n: number): string {
  return String(n).padStart(2, '0');
}

export function toIsoDate({ year, month, day }: DateParts): string {
  return `${String(year).padStart(4, '0')}-${pad2(month)}-${pad2(day)}`;
}

/** Days in a month (month is 1-12). */
export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/** A UTC Date for the calendar day, used only as an Intl formatting carrier. */
function utcCarrier(p: DateParts): Date {
  return new Date(Date.UTC(p.year, p.month - 1, p.day));
}

const fmtMedium = new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', month: 'short', day: 'numeric', year: 'numeric' });
const fmtShort = new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', month: 'short', day: 'numeric' });
const fmtWeekday = new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', weekday: 'short', month: 'short', day: 'numeric' });
const fmtMonthLong = new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', month: 'long', year: 'numeric' });
const fmtMonthAbbrev = new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', month: 'short' });

export type DateStyle = 'medium' | 'short' | 'weekday';

/** '2026-03-05' -> 'Mar 5, 2026' (medium), 'Mar 5' (short), 'Thu, Mar 5' (weekday). */
export function formatDate(iso: string | null | undefined, style: DateStyle = 'medium'): string {
  if (!iso) return EMPTY;
  const p = parseIsoDate(iso);
  if (!p) return iso;
  const d = utcCarrier(p);
  if (style === 'short') return fmtShort.format(d);
  if (style === 'weekday') return fmtWeekday.format(d);
  return fmtMedium.format(d);
}

/** '2026-03-01' -> 'March 2026' (long) or 'Mar ’26' (short; the apostrophe keeps it from reading as a day). */
export function formatMonth(iso: string | null | undefined, style: 'long' | 'short' = 'long'): string {
  if (!iso) return EMPTY;
  const p = parseIsoDate(iso);
  if (!p) return iso;
  const d = utcCarrier({ ...p, day: 1 });
  return style === 'short' ? `${fmtMonthAbbrev.format(d)} ’${String(p.year % 100).padStart(2, '0')}` : fmtMonthLong.format(d);
}

/** 'Mar 5 – Mar 18, 2026' (year shown once when both dates share it). */
export function formatDateRange(start: string | null | undefined, end: string | null | undefined): string {
  if (!start || !end) return EMPTY;
  const a = parseIsoDate(start);
  const b = parseIsoDate(end);
  if (!a || !b) return `${start} – ${end}`;
  if (a.year === b.year) return `${formatDate(start, 'short')} – ${formatDate(end, 'medium')}`;
  return `${formatDate(start)} – ${formatDate(end)}`;
}

/** Calendar-day arithmetic on ISO dates (not money). */
export function addDays(iso: string, days: number): string {
  const p = parseIsoDate(iso);
  if (!p) throw new Error(`Invalid ISO date: ${iso}`);
  const d = new Date(Date.UTC(p.year, p.month - 1, p.day + days));
  return toIsoDate({ year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() });
}

/** First-of-month ISO date for any ISO date: '2026-03-17' -> '2026-03-01'. */
export function monthStart(iso: string): string {
  const p = parseIsoDate(iso);
  if (!p) throw new Error(`Invalid ISO date: ${iso}`);
  return toIsoDate({ ...p, day: 1 });
}

/** Shift a month: addMonths('2026-01-01', -1) -> '2025-12-01'. Always returns the 1st. */
export function addMonths(iso: string, months: number): string {
  const p = parseIsoDate(iso);
  if (!p) throw new Error(`Invalid ISO date: ${iso}`);
  const d = new Date(Date.UTC(p.year, p.month - 1 + months, 1));
  return toIsoDate({ year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: 1 });
}

/** Day of week, 0 = Sunday. */
export function weekdayOf(iso: string): number {
  const p = parseIsoDate(iso);
  if (!p) throw new Error(`Invalid ISO date: ${iso}`);
  return utcCarrier(p).getUTCDay();
}

/** The browser's local calendar date as 'YYYY-MM-DD'. */
export function todayLocal(now: Date = new Date()): string {
  return toIsoDate({ year: now.getFullYear(), month: now.getMonth() + 1, day: now.getDate() });
}

/** Is this a valid first-of-month ISO date? Used to validate ?month= URL params. */
export function isMonthStart(value: string | null | undefined): value is string {
  if (!value) return false;
  const p = parseIsoDate(value);
  return p !== null && p.day === 1 && value.length === 10;
}

/** Relative wording for a day count from a view (e.g. days_until_due). */
export function formatRelativeDays(days: number | null | undefined): string {
  if (days === null || days === undefined) return EMPTY;
  if (days === 0) return 'today';
  if (days === 1) return 'tomorrow';
  if (days === -1) return 'yesterday';
  return days > 0 ? `in ${days} days` : `${Math.abs(days)} days ago`;
}

/** 'credit_card' -> 'Credit card'. */
export function humanize(value: string | null | undefined): string {
  if (!value) return EMPTY;
  const s = value.replace(/_/g, ' ');
  return s.charAt(0).toUpperCase() + s.slice(1);
}

const MS_PER_DAY = 86_400_000;

/** Days since 1970-01-01 for an ISO date: a linear x-value for time-scaled chart axes. */
export function isoToDayNumber(iso: string): number {
  const p = parseIsoDate(iso);
  if (!p) return Number.NaN;
  return Date.UTC(p.year, p.month - 1, p.day) / MS_PER_DAY;
}

/** Inverse of isoToDayNumber (for axis tick labels). */
export function dayNumberToIso(day: number): string {
  const d = new Date(Math.round(day) * MS_PER_DAY);
  return toIsoDate({ year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() });
}
