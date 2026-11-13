import { useEffect, useId, useRef, useState, type FormEvent } from 'react';
import { useView } from '../hooks/useView';
import type { AccountRow, CategoryRow, VAppInfo, VDebt, VTransaction, VUpcomingBill } from '../types/db';
import { addDays, formatCurrency, formatDate, todayLocal } from '../lib/format';
import {
  amountToInputText,
  parseAmountCents,
  sanitizeAmountInput,
  signedDollars,
  type Direction,
} from '../lib/money';
import { addManualTransaction, deleteManualTransaction, updateManualTransaction } from '../lib/writes';
import { cx } from '../lib/cx';
import { Banner, Button, Field, inputClass } from './ui';
import { Icon } from './Icon';
import { useEntry } from './EntryContext';

/**
 * Bottom sheet (mobile) / dialog (desktop) for adding or editing a manual transaction.
 * The form mounts fresh each time the sheet opens, so its state always starts from the right values.
 */
export function TransactionSheet() {
  const { sheet, closeSheet } = useEntry();
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!sheet.open) return;
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = overflow;
      previous?.focus?.();
    };
  }, [sheet.open]);

  if (!sheet.open) return null;
  const close = () => {
    if (!busy) closeSheet();
  };

  return (
    <div
      className="fixed inset-0 z-40 flex items-end justify-center md:items-center md:p-6"
      onKeyDown={(e) => {
        if (e.key === 'Escape') close();
      }}
    >
      <div className="absolute inset-0 bg-black/50" aria-hidden="true" onClick={close} />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={sheet.editing ? 'Edit entry' : 'Add transaction'}
        className="relative max-h-[94dvh] w-full max-w-lg overflow-y-auto rounded-t-2xl border border-line bg-surface p-4 pb-[max(1rem,env(safe-area-inset-bottom))] shadow-xl md:rounded-2xl"
      >
        <EntryForm key={sheet.session} editing={sheet.editing} onBusy={setBusy} />
      </div>
    </div>
  );
}

const MONEY_ACCOUNT_KINDS = new Set(['checking', 'savings', 'cash']);

function EntryForm({ editing, onBusy }: { editing: VTransaction | null; onBusy: (busy: boolean) => void }) {
  const { closeSheet, bump } = useEntry();
  const formId = useId();
  const amountRef = useRef<HTMLInputElement>(null);

  const appInfo = useView<VAppInfo>('entry:v_app_info', (sb) => sb.from('v_app_info').select('*').limit(1));
  const categories = useView<CategoryRow>('entry:categories', (sb) => sb.from('categories').select('*').order('name'));
  const accounts = useView<AccountRow>('entry:accounts', (sb) =>
    sb.from('accounts').select('*').eq('is_active', true).order('name'),
  );
  const bills = useView<VUpcomingBill>('entry:v_upcoming_bills', (sb) =>
    sb.from('v_upcoming_bills').select('*').order('due_date').order('bill_name'),
  );
  const debts = useView<VDebt>('entry:v_debts', (sb) =>
    sb.from('v_debts').select('*').eq('is_active', true).order('name'),
  );
  const recent = useView<Pick<VTransaction, 'merchant'>>('entry:recent_merchants', (sb) =>
    sb.from('v_transactions').select('merchant').not('merchant', 'is', null).order('created_at', { ascending: false }).limit(200),
  );

  const [direction, setDirection] = useState<Direction>(editing && editing.amount > 0 ? 'income' : 'expense');
  const [amountText, setAmountText] = useState(editing ? amountToInputText(editing.amount) : '');
  const [merchant, setMerchant] = useState(editing ? (editing.merchant ?? editing.description_raw) : '');
  const [date, setDate] = useState(editing?.txn_date ?? '');
  const [categoryId, setCategoryId] = useState(editing?.category_id ?? '');
  const [accountId, setAccountId] = useState(editing?.account_id ?? '');
  const [note, setNote] = useState(editing?.note ?? '');
  const [cleared, setCleared] = useState(editing?.cleared ?? false);
  const [billId, setBillId] = useState(editing?.bill_occurrence_id ?? '');
  const [debtId, setDebtId] = useState(editing?.debt_id ?? '');
  const [showMore, setShowMore] = useState(Boolean(editing?.bill_occurrence_id || editing?.debt_id));
  const [busy, setBusy] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState<string | null>(null);

  const today = appInfo.data?.[0]?.today ?? todayLocal();
  const effectiveDate = date || today;
  const moneyAccounts = (accounts.data ?? []).filter((a) => MONEY_ACCOUNT_KINDS.has(a.kind));
  const defaultAccount = moneyAccounts.find((a) => a.kind === 'checking') ?? moneyAccounts[0] ?? null;
  const effectiveAccountId = accountId || defaultAccount?.id || '';
  const accountName = moneyAccounts.find((a) => a.id === effectiveAccountId)?.name ?? editing?.account_name ?? '';

  const categoryOptions = (categories.data ?? []).filter((c) => (direction === 'income' ? c.kind === 'income' : c.kind !== 'income'));
  const merchantSuggestions = Array.from(new Set((recent.data ?? []).map((r) => r.merchant).filter((m): m is string => Boolean(m)))).slice(0, 40);
  const billList = bills.data ?? [];
  const linkedBillMissing = billId !== '' && !billList.some((b) => b.occurrence_id === billId);

  function changeDirection(next: Direction) {
    setDirection(next);
    const current = (categories.data ?? []).find((c) => c.id === categoryId);
    if (current && (next === 'income') !== (current.kind === 'income')) setCategoryId('');
    if (next === 'income') {
      setBillId('');
      setDebtId('');
    }
  }

  function chooseBill(id: string) {
    setBillId(id);
    const bill = billList.find((b) => b.occurrence_id === id);
    if (!bill) return;
    if (!merchant.trim()) setMerchant(bill.bill_name);
    if (!amountText) setAmountText(amountToInputText(bill.remaining_amount));
    if (!categoryId && bill.category_id) setCategoryId(bill.category_id);
  }

  function chooseDebt(id: string) {
    setDebtId(id);
    const debt = (debts.data ?? []).find((d) => d.debt_id === id);
    if (debt && !merchant.trim()) setMerchant(debt.name);
  }

  async function save(addAnother: boolean) {
    setError(null);
    setSaved(null);
    const cents = parseAmountCents(amountText);
    if (cents === null) {
      setError('Enter an amount above $0.00.');
      amountRef.current?.focus();
      return;
    }
    const name = merchant.trim();
    if (!name) {
      setError(direction === 'income' ? 'Enter who paid you.' : 'Enter who you paid.');
      return;
    }
    if (effectiveDate > today) {
      setError('The date cannot be in the future.');
      return;
    }
    setBusy(true);
    onBusy(true);
    const common = {
      amount: signedDollars(cents, direction),
      txnDate: effectiveDate,
      merchant: name,
      categoryId: categoryId || null,
      note: note.trim() || null,
      cleared,
      billOccurrenceId: direction === 'expense' && billId ? billId : null,
      debtId: direction === 'expense' && debtId ? debtId : null,
    };
    const res = editing
      ? await updateManualTransaction(editing.id, common)
      : await addManualTransaction({ ...common, accountId: effectiveAccountId || null });
    setBusy(false);
    onBusy(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    bump();
    if (addAnother && !editing) {
      setSaved(`Saved ${formatCurrency(signedDollars(cents, direction))} · ${name}`);
      setAmountText('');
      setMerchant('');
      setNote('');
      setBillId('');
      setDebtId('');
      setCleared(false);
      amountRef.current?.focus();
    } else {
      closeSheet();
    }
  }

  async function remove() {
    if (!editing) return;
    if (!confirmDelete) {
      setConfirmDelete(true);
      return;
    }
    setBusy(true);
    onBusy(true);
    const res = await deleteManualTransaction(editing.id);
    setBusy(false);
    onBusy(false);
    if (!res.ok) {
      setError(res.error);
      setConfirmDelete(false);
      return;
    }
    bump();
    closeSheet();
  }

  const onSubmit = (e: FormEvent) => {
    e.preventDefault();
    void save(false);
  };

  const sign = direction === 'expense' ? '−' : '+';

  return (
    <form id={formId} onSubmit={onSubmit} className="space-y-4" noValidate>
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-base font-semibold text-ink">{editing ? 'Edit entry' : 'Add transaction'}</h2>
        <button
          type="button"
          onClick={() => !busy && closeSheet()}
          aria-label="Close"
          className="grid h-10 w-10 place-items-center rounded-lg text-muted hover:bg-surface-2 hover:text-ink focus-visible:outline-2 focus-visible:outline-accent"
        >
          <Icon name="close" size={20} />
        </button>
      </div>

      <div role="radiogroup" aria-label="Type" className="grid grid-cols-2 gap-1 rounded-xl bg-surface-2 p-1">
        {(['expense', 'income'] as const).map((d) => (
          <button
            key={d}
            type="button"
            role="radio"
            aria-checked={direction === d}
            onClick={() => changeDirection(d)}
            className={cx(
              'min-h-11 rounded-lg text-sm font-semibold focus-visible:outline-2 focus-visible:outline-accent',
              direction === d ? 'bg-surface text-ink shadow-sm' : 'text-muted',
            )}
          >
            {d === 'expense' ? 'Expense' : 'Income'}
          </button>
        ))}
      </div>

      <label className="block">
        <span className="sr-only">Amount in dollars</span>
        <span className="flex items-baseline justify-center gap-1 rounded-xl border border-line bg-surface-2 px-3 py-3 focus-within:outline-2 focus-within:outline-accent">
          <span className={cx('text-3xl font-semibold', direction === 'income' ? 'text-pos' : 'text-muted')} aria-hidden="true">
            {sign}$
          </span>
          <input
            ref={amountRef}
            value={amountText}
            onChange={(e) => setAmountText(sanitizeAmountInput(e.target.value))}
            inputMode="decimal"
            pattern="[0-9]*[.,]?[0-9]*"
            autoComplete="off"
            enterKeyHint="done"
            placeholder="0.00"
            autoFocus
            className="w-full min-w-0 bg-transparent text-center text-4xl font-semibold tabular-nums text-ink outline-none placeholder:text-subtle"
          />
        </span>
      </label>

      <Field label={direction === 'income' ? 'From' : 'Paid to'}>
        <input
          className={inputClass}
          value={merchant}
          onChange={(e) => setMerchant(e.target.value)}
          list={`${formId}-merchants`}
          maxLength={120}
          autoComplete="off"
          autoCapitalize="words"
          enterKeyHint="next"
          placeholder={direction === 'income' ? 'e.g. Side job' : 'e.g. Casey’s'}
        />
        <datalist id={`${formId}-merchants`}>
          {merchantSuggestions.map((m) => (
            <option key={m} value={m} />
          ))}
        </datalist>
      </Field>

      <div>
        <div className="mb-1 text-xs font-medium text-muted">Date</div>
        <div className="flex flex-wrap items-center gap-2">
          {([
            ['Today', today],
            ['Yesterday', addDays(today, -1)],
          ] as const).map(([label, value]) => (
            <button
              key={label}
              type="button"
              onClick={() => setDate(value)}
              aria-pressed={effectiveDate === value}
              className={cx(
                'min-h-10 rounded-lg border px-3 text-sm font-medium focus-visible:outline-2 focus-visible:outline-accent',
                effectiveDate === value ? 'border-accent bg-accent-soft text-ink' : 'border-line text-muted',
              )}
            >
              {label}
            </button>
          ))}
          <input
            type="date"
            aria-label="Date"
            className={cx(inputClass, 'w-auto flex-1 basis-36')}
            value={effectiveDate}
            max={today}
            onChange={(e) => setDate(e.target.value)}
          />
        </div>
        <div className="mt-1 text-xs text-muted">{formatDate(effectiveDate, 'weekday')}</div>
      </div>

      <Field label="Category">
        <select className={inputClass} value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
          <option value="">{categories.loading ? 'Loading…' : 'Uncategorized'}</option>
          {categoryOptions.map((c) => (
            <option key={c.id} value={c.id}>
              {c.parent_name ? `${c.parent_name} › ${c.name}` : c.name}
            </option>
          ))}
        </select>
      </Field>

      {editing ? (
        <div className="text-xs text-muted">Account: {accountName}</div>
      ) : moneyAccounts.length > 1 ? (
        <Field label="Account">
          <select className={inputClass} value={effectiveAccountId} onChange={(e) => setAccountId(e.target.value)}>
            {moneyAccounts.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name}
              </option>
            ))}
          </select>
        </Field>
      ) : accountName ? (
        <div className="text-xs text-muted">Account: {accountName}</div>
      ) : null}

      <Field label="Note (optional)">
        <input className={inputClass} value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} autoComplete="off" enterKeyHint="done" />
      </Field>

      <label className="flex min-h-11 cursor-pointer items-center gap-3 rounded-lg border border-line px-3 text-sm text-ink">
        <input type="checkbox" checked={cleared} onChange={(e) => setCleared(e.target.checked)} className="h-5 w-5 accent-[var(--accent)]" />
        Already cleared at my bank
      </label>

      {direction === 'expense' ? (
        <div>
          <button
            type="button"
            onClick={() => setShowMore((v) => !v)}
            aria-expanded={showMore}
            className="flex min-h-10 items-center gap-1 text-sm font-medium text-accent focus-visible:outline-2 focus-visible:outline-accent"
          >
            <Icon name="chevronRight" size={16} className={cx('transition-transform', showMore && 'rotate-90')} />
            Pays a bill or debt
          </button>
          {showMore ? (
            <div className="mt-2 space-y-3 rounded-xl border border-line p-3">
              <Field label="Bill">
                <select className={inputClass} value={billId} onChange={(e) => chooseBill(e.target.value)}>
                  <option value="">Not a bill</option>
                  {linkedBillMissing ? <option value={billId}>Currently linked bill</option> : null}
                  {billList.map((b) => (
                    <option key={b.occurrence_id} value={b.occurrence_id}>
                      {b.bill_name} · {formatDate(b.due_date, 'short')} · {formatCurrency(b.remaining_amount)} left
                    </option>
                  ))}
                </select>
              </Field>
              <Field label="Debt payment">
                <select className={inputClass} value={debtId} onChange={(e) => chooseDebt(e.target.value)}>
                  <option value="">Not a debt payment</option>
                  {(debts.data ?? []).map((d) => (
                    <option key={d.debt_id} value={d.debt_id}>
                      {d.name}
                    </option>
                  ))}
                </select>
              </Field>
              <p className="text-xs text-muted">Linking a bill marks it paid so the forecast stops counting it as still due.</p>
            </div>
          ) : null}
        </div>
      ) : null}

      <div aria-live="polite" className="min-h-0">
        {saved ? <p className="text-sm font-medium text-pos">{saved}</p> : null}
      </div>
      {error ? <Banner tone="danger" title="Not saved">{error}</Banner> : null}

      <div className="flex flex-col gap-2 sm:flex-row-reverse">
        <Button type="submit" variant="primary" disabled={busy} className="min-h-12 flex-1 text-base">
          {busy ? 'Saving…' : editing ? 'Save changes' : 'Save'}
        </Button>
        {!editing ? (
          <Button onClick={() => void save(true)} disabled={busy} className="min-h-12 flex-1">
            Save & add another
          </Button>
        ) : (
          <Button onClick={() => void remove()} disabled={busy} className={cx('min-h-12 flex-1', confirmDelete && 'border-danger-line text-danger')}>
            {confirmDelete ? 'Tap again to delete' : 'Delete entry'}
          </Button>
        )}
      </div>
    </form>
  );
}
