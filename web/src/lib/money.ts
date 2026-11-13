/**
 * Amount-entry helpers for the manual transaction form. Pure functions, no state.
 *
 * Money is kept as integer cents while the user types so no floating-point sum ever happens in the
 * browser; the only arithmetic is cents <-> dollars for display and for the single number sent to the
 * database. The database validates and stores the value (numeric(12,2)); it does all other math.
 */

/** Largest amount the form accepts: 9 whole digits (matches the database's 1,000,000 cap with room to spare). */
const MAX_INT_DIGITS = 9;

/**
 * Keep only what a money field can hold: digits and one decimal point, at most two decimals.
 * A comma is treated as the decimal point (some phone keypads show it), pasted "$1,234.50"-style
 * thousands separators are not supported and are simply dropped with the other characters.
 */
export function sanitizeAmountInput(raw: string): string {
  const cleaned = raw.replace(/,/g, '.').replace(/[^\d.]/g, '');
  const hasDot = cleaned.includes('.');
  const [intRaw = '', ...rest] = cleaned.split('.');
  const decimals = rest.join('').slice(0, 2);
  const whole = intRaw.replace(/^0+(?=\d)/, '').slice(0, MAX_INT_DIGITS);
  return hasDot ? `${whole}.${decimals}` : whole;
}

/** "12.3" -> 1230, "0.05" -> 5, ".5" -> 50, "" / "." / "0" / "0.00" -> null (an amount must be above zero). */
export function parseAmountCents(text: string): number | null {
  const t = text.trim();
  if (!/^\d*\.?\d{0,2}$/.test(t) || !/\d/.test(t)) return null;
  const [whole = '', dec = ''] = t.split('.');
  const cents = Number(whole || '0') * 100 + Number(dec.padEnd(2, '0') || '0');
  return Number.isSafeInteger(cents) && cents > 0 ? cents : null;
}

/** Like parseAmountCents, but 0 is a valid answer: "0" / "0.00" -> 0, "" / "." -> null. For per-paycheck amounts and caps. */
export function parseCentsAllowZero(text: string): number | null {
  const t = text.trim();
  if (!/^\d*\.?\d{0,2}$/.test(t) || !/\d/.test(t)) return null;
  const [whole = '', dec = ''] = t.split('.');
  const cents = Number(whole || '0') * 100 + Number(dec.padEnd(2, '0') || '0');
  return Number.isSafeInteger(cents) ? cents : null;
}

/** Integer cents -> the dollar number sent to the database (1230 -> 12.3). */
export function centsToDollars(cents: number): number {
  return cents / 100;
}

export type Direction = 'expense' | 'income';

/** Cents plus a direction -> the signed dollar amount the database expects (negative = money out). */
export function signedDollars(cents: number, direction: Direction): number {
  const dollars = cents / 100;
  return direction === 'expense' ? -dollars : dollars;
}

/** A stored amount (any sign) -> the text for an amount field: -15 -> "15.00". */
export function amountToInputText(amount: number): string {
  return (Math.abs(Math.round(amount * 100)) / 100).toFixed(2);
}
