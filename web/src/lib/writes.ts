/**
 * The web app's only write path (and the only file allowed to call database functions; see tests/readonly-guard.test.ts
 * and eslint.config.js). Tables are SELECT-only for the signed-in user. Everything here calls one of five
 * narrow, owner-checked SECURITY DEFINER functions from 20261113000000_manual_entry_and_envelopes.sql:
 *
 *   add_manual_transaction / update_manual_transaction / delete_manual_transaction
 *   set_transaction_cleared
 *   move_envelope_money
 *
 * None of them can set `reconciled`; only Claude can (a trigger blocks it for any web session). The database
 * validates every argument again, so the checks here only exist to give friendlier messages.
 *
 * Each call resolves to a result object and never throws, so forms can show the message inline.
 */
import { supabase } from './supabase';
import type { IsoDate, Uuid } from '../types/db';

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
