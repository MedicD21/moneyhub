/**
 * The web app's only write path (and the only file allowed to call database functions; see tests/readonly-guard.test.ts
 * and eslint.config.js). Tables are SELECT-only for the signed-in user. Everything here calls one of the
 * narrow, owner-checked SECURITY DEFINER functions (thirteen):
 *
 *   add_manual_transaction / update_manual_transaction / delete_manual_transaction   (20261113000000)
 *   set_transaction_cleared                                                           (20261113000000)
 *   move_envelope_money                                                               (20261113030000)
 *   create_envelope / update_envelope                                                 (20261113040000)
 *   create_set_aside / update_set_aside                                               (20261113050000)
 *   delete_set_aside (paused set-asides only)                                         (20261127190000)
 *   review_transaction / create_merchant_rule                                         (20261115000000)
 *   save_shortfall_plan (the Planner's saved plan: hours and spending per paycheck)  (20261127210000)
 *
 * None of them can set `reconciled`; only Claude can (a trigger blocks it for any web session). Rows from the bank
 * (imported or reconciled) can only be reclassified here: their amount, date, merchant and status never change from
 * the web app. The database
 * validates every argument again, so the checks here only exist to give friendlier messages.
 *
 * Each call resolves to a result object and never throws, so forms can show the message inline.
 */
import { supabase } from './supabase';
import type { IsoDate, SetAsideArgs, ShortfallPlanEntry, Uuid } from '../types/db';

export type WriteResult<T = void> = { ok: true; data: T } | { ok: false; error: string };

type PgError = { message: string; code?: string };

const NO_CLIENT: WriteResult<never> = { ok: false, error: 'Supabase is not configured.' };

function fail(error: PgError): WriteResult<never> {
  if (error.code === '42501' && /owner/i.test(error.message)) {
    return { ok: false, error: 'Your session has expired. Sign in again and retry.' };
  }
  if (error.code === '42501' || /permission denied/i.test(error.message)) {
    return { ok: false, error: 'That change is not allowed.' };
  }
  return { ok: false, error: error.message || 'The change could not be saved.' };
}

function networkFail(e: unknown): WriteResult<never> {
  return {
    ok: false,
    error: e instanceof Error && e.message ? `Network error: ${e.message}` : 'Network error: could not reach Supabase.',
  };
}

export type ManualEntryInput = {
  /** signed dollars: negative = money out, positive = money in */
  amount: number;
  txnDate: IsoDate;
  merchant: string;
  accountId?: Uuid | null;
  categoryId?: Uuid | null;
  note?: string | null;
  cleared?: boolean;
  billOccurrenceId?: Uuid | null;
  debtId?: Uuid | null;
};

function checkAmount(amount: number): string | null {
  if (!Number.isFinite(amount) || amount === 0) return 'Enter an amount.';
  return null;
}

export async function addManualTransaction(input: ManualEntryInput): Promise<WriteResult<Uuid>> {
  if (!supabase) return NO_CLIENT;
  const bad = checkAmount(input.amount);
  if (bad) return { ok: false, error: bad };
  try {
    const { data, error } = await supabase.rpc('add_manual_transaction', {
      p_amount: input.amount,
      p_txn_date: input.txnDate,
      p_merchant: input.merchant,
      p_account_id: input.accountId ?? null,
      p_category_id: input.categoryId ?? null,
      p_note: input.note ?? null,
      p_cleared: input.cleared ?? false,
      p_bill_occurrence_id: input.billOccurrenceId ?? null,
      p_debt_id: input.debtId ?? null,
    });
    if (error) return fail(error);
    return { ok: true, data };
  } catch (e) {
    return networkFail(e);
  }
}

export async function updateManualTransaction(id: Uuid, input: Omit<ManualEntryInput, 'accountId'>): Promise<WriteResult<Uuid>> {
  if (!supabase) return NO_CLIENT;
  const bad = checkAmount(input.amount);
  if (bad) return { ok: false, error: bad };
  try {
    const { data, error } = await supabase.rpc('update_manual_transaction', {
      p_id: id,
      p_amount: input.amount,
      p_txn_date: input.txnDate,
      p_merchant: input.merchant,
      p_category_id: input.categoryId ?? null,
      p_note: input.note ?? null,
      p_cleared: input.cleared ?? false,
      p_bill_occurrence_id: input.billOccurrenceId ?? null,
      p_debt_id: input.debtId ?? null,
    });
    if (error) return fail(error);
    return { ok: true, data };
  } catch (e) {
    return networkFail(e);
  }
}

export async function deleteManualTransaction(id: Uuid): Promise<WriteResult> {
  if (!supabase) return NO_CLIENT;
  try {
    const { error } = await supabase.rpc('delete_manual_transaction', { p_id: id });
    if (error) return fail(error);
    return { ok: true, data: undefined };
  } catch (e) {
    return networkFail(e);
  }
}

export async function setTransactionCleared(id: Uuid, cleared: boolean): Promise<WriteResult> {
  if (!supabase) return NO_CLIENT;
  try {
    const { error } = await supabase.rpc('set_transaction_cleared', { p_id: id, p_cleared: cleared });
    if (error) return fail(error);
    return { ok: true, data: undefined };
  } catch (e) {
    return networkFail(e);
  }
}

/** Move money into (positive) or out of (negative) an envelope. Resolves to the envelope's new balance. */
export async function moveEnvelopeMoney(
  envelopeId: Uuid,
  amount: number,
  note?: string | null,
): Promise<WriteResult<number>> {
  if (!supabase) return NO_CLIENT;
  const bad = checkAmount(amount);
  if (bad) return { ok: false, error: bad };
  try {
    const { data, error } = await supabase.rpc('move_envelope_money', {
      p_envelope_id: envelopeId,
      p_amount: amount,
      p_note: note ?? null,
    });
    if (error) return fail(error);
    return { ok: true, data };
  } catch (e) {
    return networkFail(e);
  }
}

/** Create a goal envelope (a user-named savings pot). It starts at $0. Resolves to the new id. */
export async function createEnvelope(name: string): Promise<WriteResult<Uuid>> {
  if (!supabase) return NO_CLIENT;
  if (!name.trim()) return { ok: false, error: 'Enter a name.' };
  try {
    const { data, error } = await supabase.rpc('create_envelope', { p_name: name });
    if (error) return fail(error);
    return { ok: true, data };
  } catch (e) {
    return networkFail(e);
  }
}

/** Rename, archive (isActive false; the balance must be $0) or restore a goal envelope. */
export async function updateEnvelope(id: Uuid, name: string, isActive: boolean): Promise<WriteResult> {
  if (!supabase) return NO_CLIENT;
  if (!name.trim()) return { ok: false, error: 'Enter a name.' };
  try {
    const { error } = await supabase.rpc('update_envelope', { p_id: id, p_name: name, p_is_active: isActive });
    if (error) return fail(error);
    return { ok: true, data: undefined };
  } catch (e) {
    return networkFail(e);
  }
}

export type SetAsideInput = {
  name: string;
  perPaycheck: number;
  cap: number | null;
  startDate: IsoDate;
  openingBalance: number;
  categoryId: Uuid | null;
};

function setAsideArgs(input: SetAsideInput): SetAsideArgs {
  return {
    p_name: input.name,
    p_per_paycheck: input.perPaycheck,
    p_cap: input.cap,
    p_start_date: input.startDate,
    p_opening_balance: input.openingBalance,
    p_category_id: input.categoryId,
  };
}

/** Create an active set-aside (a per-paycheck reservation). Resolves to the new id. */
export async function createSetAside(input: SetAsideInput): Promise<WriteResult<Uuid>> {
  if (!supabase) return NO_CLIENT;
  if (!input.name.trim()) return { ok: false, error: 'Enter a name.' };
  try {
    const { data, error } = await supabase.rpc('create_set_aside', setAsideArgs(input));
    if (error) return fail(error);
    return { ok: true, data };
  } catch (e) {
    return networkFail(e);
  }
}

/** Edit a set-aside, or pause (isActive false) / resume it. Delete is a separate step: deleteSetAside. */
export async function updateSetAside(id: Uuid, input: SetAsideInput, isActive: boolean): Promise<WriteResult> {
  if (!supabase) return NO_CLIENT;
  if (!input.name.trim()) return { ok: false, error: 'Enter a name.' };
  try {
    const { error } = await supabase.rpc('update_set_aside', { ...setAsideArgs(input), p_id: id, p_is_active: isActive });
    if (error) return fail(error);
    return { ok: true, data: undefined };
  } catch (e) {
    return networkFail(e);
  }
}

/** Permanently delete a paused set-aside. The database refuses an active one, or one with bank-reconciled transactions tagged to it. */
export async function deleteSetAside(id: Uuid): Promise<WriteResult> {
  if (!supabase) return NO_CLIENT;
  try {
    const { error } = await supabase.rpc('delete_set_aside', { p_id: id });
    if (error) return fail(error);
    return { ok: true, data: undefined };
  } catch (e) {
    return networkFail(e);
  }
}

export type ReviewInput = {
  categoryId: Uuid | null;
  note: string | null;
  billOccurrenceId: Uuid | null;
  debtId: Uuid | null;
  /** true (default) clears the review flag and question */
  resolve?: boolean;
};

/**
 * Classify any transaction (imported or manual, reconciled or not): category, note, bill or debt link.
 * Never changes amount, date, merchant, status, cleared or reconciliation.
 */
export async function reviewTransaction(id: Uuid, input: ReviewInput): Promise<WriteResult<Uuid>> {
  if (!supabase) return NO_CLIENT;
  try {
    const { data, error } = await supabase.rpc('review_transaction', {
      p_id: id,
      p_category_id: input.categoryId,
      p_note: input.note,
      p_bill_occurrence_id: input.billOccurrenceId,
      p_debt_id: input.debtId,
      p_resolve: input.resolve ?? true,
    });
    if (error) return fail(error);
    return { ok: true, data };
  } catch (e) {
    return networkFail(e);
  }
}

export type MerchantRuleInput = {
  /** case-insensitive text found in the bank description */
  pattern: string;
  categoryId: Uuid;
  merchant?: string | null;
  /** also categorize other open, uncategorized review rows that match */
  applyToOpen?: boolean;
};

/** Save "always do this for this merchant". Resolves to how many open review rows the rule also sorted. */
export async function createMerchantRule(input: MerchantRuleInput): Promise<WriteResult<number>> {
  if (!supabase) return NO_CLIENT;
  if (input.pattern.trim().length < 2) return { ok: false, error: 'Enter at least 2 characters to match.' };
  try {
    const { data, error } = await supabase.rpc('create_merchant_rule', {
      p_pattern: input.pattern,
      p_category_id: input.categoryId,
      p_merchant: input.merchant ?? null,
      p_apply_to_open: input.applyToOpen ?? false,
    });
    if (error) return fail(error);
    return { ok: true, data };
  } catch (e) {
    return networkFail(e);
  }
}

/**
 * Save the Planner's plan (replaces the stored one). Only hours and spending per paycheck are stored; the
 * database validates them and zero rows are dropped. Resolves to the save time (ISO timestamp).
 */
export async function saveShortfallPlan(entries: ShortfallPlanEntry[]): Promise<WriteResult<string>> {
  if (!supabase) return NO_CLIENT;
  try {
    const { data, error } = await supabase.rpc('save_shortfall_plan', { p_paychecks: entries });
    if (error) return fail(error);
    return { ok: true, data };
  } catch (e) {
    return networkFail(e);
  }
}
