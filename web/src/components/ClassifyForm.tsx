import { useId, useState, type FormEvent } from 'react';
import { useView } from '../hooks/useView';
import type { CategoryRow, VDebt, VTransaction, VUpcomingBill } from '../types/db';
import { formatCurrency, formatDate } from '../lib/format';
import { createMerchantRule, reviewTransaction } from '../lib/writes';
import { isBankLocked, patternMatches, rankCategories, suggestRulePattern } from '../lib/review';
import { cx } from '../lib/cx';
import { Badge, Banner, Button, Field, Money, inputClass } from './ui';
import { Icon } from './Icon';
import { useEntry } from './EntryContext';

export type ClassifyOutcome = {
  /** open review rows the new merchant rule also sorted; null when no rule was asked for */
  ruleCount: number | null;
  /** set when the transaction saved but the rule did not (the form then shows it and stays usable) */
  ruleError: string | null;
};

/**
 * Classification-only edit for any transaction (imported or manual, reconciled or not): category, note,
 * bill or debt link, and optionally a merchant rule. Amount, date and merchant are shown read-only; the
 * database (review_transaction) never changes them. Mount it with a `key` per transaction so state resets.
 */
export function ClassifyForm({
  t,
  submitLabel,
  onSaved,
  onSkip,
  onClose,
  onBusy,
  heading,
}: {
  t: VTransaction;
  submitLabel: string;
  onSaved: (outcome: ClassifyOutcome) => void;
  onSkip?: () => void;
  onClose?: () => void;
  onBusy?: (busy: boolean) => void;
  heading?: string;
}) {
  const { bump } = useEntry();
  const formId = useId();
  const moneyOut = t.amount < 0;
  const merchantName = t.merchant ?? t.description_raw;

  const categories = useView<CategoryRow>('classify:categories', (sb) => sb.from('categories').select('*').order('name'));
  const recent = useView<Pick<VTransaction, 'category_id'>>('classify:recent_categories', (sb) =>
    sb.from('v_transactions').select('category_id').not('category_id', 'is', null).order('txn_date', { ascending: false }).limit(300),
  );
  const bills = useView<VUpcomingBill>(moneyOut ? 'classify:v_upcoming_bills' : null, (sb) =>
    sb.from('v_upcoming_bills').select('*').order('due_date').order('bill_name'),
  );
  const debts = useView<VDebt>(moneyOut ? 'classify:v_debts' : null, (sb) =>
    sb.from('v_debts').select('*').eq('is_active', true).order('name'),
  );

  const [categoryId, setCategoryId] = useState(t.category_id ?? '');
  const [note, setNote] = useState(t.note ?? '');
  const [billId, setBillId] = useState(moneyOut ? (t.bill_occurrence_id ?? '') : '');
  // Only for an extra payment with no bill. A bill that pays a debt carries the debt; the database decides it.
  const [debtId, setDebtId] = useState(moneyOut && !t.bill_occurrence_id ? (t.debt_id ?? '') : '');
  const [showLinks, setShowLinks] = useState(Boolean(t.bill_occurrence_id || t.debt_id));
  const [makeRule, setMakeRule] = useState(false);
  const [pattern, setPattern] = useState(() => suggestRulePattern(t.merchant, t.description_raw));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<{ title: string; message: string } | null>(null);

  const { frequent, rest } = rankCategories(
    categories.data ?? [],
    (recent.data ?? []).map((r) => r.category_id),
    !moneyOut,
  );
  const allShown = [...frequent, ...rest];
  const currentMissing = categoryId !== '' && !allShown.some((c) => c.id === categoryId);

  const billList = bills.data ?? [];
  const selectedBill = billList.find((b) => b.occurrence_id === billId) ?? null;
  const linkedBillMissing = billId !== '' && !selectedBill;
  // Display only: the debt the chosen bill pays. The stored debt_id is set by the database.
  const billDebtId = selectedBill ? selectedBill.debt_id : linkedBillMissing ? t.debt_id : null;
  const billDebtName = billDebtId ? ((debts.data ?? []).find((d) => d.debt_id === billDebtId)?.name ?? 'Linked debt') : null;
  const patternOk = patternMatches(pattern, t.description_raw);

  function setBusyBoth(v: boolean) {
    setBusy(v);
    onBusy?.(v);
  }

  async function save() {
    setError(null);
    if (makeRule) {
      if (!categoryId) {
        setError({ title: 'Not saved', message: 'Choose a category for the rule.' });
        return;
      }
      if (pattern.trim().length < 2) {
        setError({ title: 'Not saved', message: 'Enter at least 2 characters to match.' });
        return;
      }
    }
    setBusyBoth(true);
    const res = await reviewTransaction(t.id, {
      categoryId: categoryId || null,
      note: note.trim() || null,
      billOccurrenceId: moneyOut && billId ? billId : null,
      debtId: moneyOut && !billId && debtId ? debtId : null,
      resolve: true,
    });
    if (!res.ok) {
      setBusyBoth(false);
      setError({ title: 'Not saved', message: res.error });
      return;
    }
    // The rule runs after the save, so its count is only the other open rows it sorted.
    let outcome: ClassifyOutcome = { ruleCount: null, ruleError: null };
    if (makeRule && categoryId) {
      const rule = await createMerchantRule({ pattern, categoryId, merchant: merchantName, applyToOpen: true });
      outcome = rule.ok ? { ruleCount: rule.data, ruleError: null } : { ruleCount: null, ruleError: rule.error };
      if (!rule.ok) {
        // The transaction is saved; only the rule failed. Say so, and do not retry the rule on the next save.
        setMakeRule(false);
        setError({ title: 'Saved, but the rule was not', message: rule.error });
      }
    }
    setBusyBoth(false);
    bump();
    onSaved(outcome);
  }

  const onSubmit = (e: FormEvent) => {
    e.preventDefault();
    void save();
  };

  const chip = (c: CategoryRow) => {
    const on = categoryId === c.id;
    return (
      <button
        key={c.id}
        type="button"
        role="radio"
        aria-checked={on}
        onClick={() => setCategoryId(on ? '' : c.id)}
        className={cx(
          'min-h-11 rounded-xl px-3 text-sm font-medium transition-colors duration-200 focus-visible:outline-2 focus-visible:outline-accent-bright',
          on ? 'nav-lit text-ink' : 'btn-glass text-muted hover:text-ink',
        )}
      >
        {c.name}
      </button>
    );
  };

  return (
    <form id={formId} onSubmit={onSubmit} className="space-y-4" noValidate>
      {heading || onClose ? (
        <div className="flex items-center justify-between gap-3">
          {heading ? <h2 className="text-lg font-semibold tracking-tight text-ink">{heading}</h2> : <span />}
          {onClose ? (
            <button
              type="button"
              onClick={() => !busy && onClose()}
              aria-label="Close"
              className="btn-glass grid h-11 w-11 place-items-center rounded-xl text-muted hover:text-ink focus-visible:outline-2 focus-visible:outline-accent-bright"
            >
              <Icon name="close" size={20} />
            </button>
          ) : null}
        </div>
      ) : null}

      {/* Read-only facts from the bank */}
      <div className="rounded-2xl border border-line bg-surface-2 p-3">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="truncate text-base font-semibold text-ink" title={t.description_raw}>
                {merchantName}
              </span>
              <Badge tone={t.status === 'pending' ? 'warn' : 'muted'}>{t.status === 'pending' ? 'Pending' : 'Posted'}</Badge>
              {t.reconciled ? (
                <Badge tone="muted">
                  <Icon name="lock" size={12} /> Reconciled
                </Badge>
              ) : null}
            </div>
            <div className="mt-0.5 text-xs text-muted">
              {formatDate(t.txn_date, 'weekday')} · {t.account_name}
            </div>
            {t.merchant && t.merchant !== t.description_raw ? (
              <div className="mt-0.5 truncate text-xs text-subtle">{t.description_raw}</div>
            ) : null}
          </div>
          <Money value={t.amount} signed showPlus className="shrink-0 text-lg font-semibold" />
        </div>
        {isBankLocked(t) ? (
          <p className="mt-2 flex items-center gap-1.5 text-xs text-muted">
            <Icon name="lock" size={14} /> From your bank. Ask Claude to fix a wrong amount or date.
          </p>
        ) : null}
      </div>

      {t.needs_review && t.review_question ? (
        <div className="rounded-2xl border border-warn-line bg-warn-bg px-4 py-3">
          <div className="text-xs font-medium text-warn">Claude asks</div>
          <p className="mt-0.5 text-base font-semibold text-ink">{t.review_question}</p>
        </div>
      ) : null}

      <div>
        <div id={`${formId}-cat`} className="mb-1.5 text-xs font-medium text-muted">
          Category
        </div>
        {categories.loading ? (
          <p className="text-sm text-muted">Loading categories…</p>
        ) : categories.error ? (
          <Banner tone="danger" title="Couldn’t load categories">
            <button type="button" className="underline" onClick={categories.reload}>
              Retry
            </button>
          </Banner>
        ) : (
          <div role="radiogroup" aria-labelledby={`${formId}-cat`} className="space-y-2">
            {frequent.length > 0 ? <div className="flex flex-wrap gap-2">{frequent.map(chip)}</div> : null}
            {frequent.length > 0 && rest.length > 0 ? <div className="text-xs text-subtle">All categories</div> : null}
            <div className="flex flex-wrap gap-2">{rest.map(chip)}</div>
            {currentMissing ? (
              <p className="text-xs text-muted">
                Current: {t.category_name ?? 'another category'}. Pick one above to change it.
              </p>
            ) : null}
          </div>
        )}
      </div>

      <Field label="Note (optional)">
        <input
          className={inputClass}
          value={note}
          onChange={(e) => setNote(e.target.value)}
          maxLength={500}
          autoComplete="off"
          enterKeyHint="done"
        />
      </Field>

      {moneyOut ? (
        <div>
          <button
            type="button"
            onClick={() => setShowLinks((v) => !v)}
            aria-expanded={showLinks}
            className="flex min-h-11 items-center gap-1 text-sm font-medium text-accent focus-visible:outline-2 focus-visible:outline-accent"
          >
            <Icon name="chevronRight" size={16} className={cx('transition-transform motion-reduce:transition-none', showLinks && 'rotate-90')} />
            Pays a bill or debt
          </button>
          {showLinks ? (
            <div className="page-enter mt-2 space-y-3 rounded-2xl border border-line bg-surface-2 p-3">
              <Field label="Bill">
                <select
                  className={inputClass}
                  value={billId}
                  onChange={(e) => {
                    setBillId(e.target.value);
                    if (e.target.value) setDebtId('');
                  }}
                >
                  <option value="">Not a bill</option>
                  {linkedBillMissing ? <option value={billId}>Currently linked bill</option> : null}
                  {billList.map((b) => (
                    <option key={b.occurrence_id} value={b.occurrence_id}>
                      {b.bill_name} · {formatDate(b.due_date, 'short')} · {formatCurrency(b.remaining_amount)} left
                    </option>
                  ))}
                </select>
              </Field>
              {billDebtName ? (
                <div className="text-sm text-ink">
                  <span className="text-xs font-medium text-muted">Pays debt</span>
                  <div>{billDebtName}</div>
                </div>
              ) : null}
              {!billId ? (
                <Field label="Extra payment toward a debt">
                  <select className={inputClass} value={debtId} onChange={(e) => setDebtId(e.target.value)}>
                    <option value="">Not a debt payment</option>
                    {(debts.data ?? []).map((d) => (
                      <option key={d.debt_id} value={d.debt_id}>
                        {d.name}
                      </option>
                    ))}
                  </select>
                  <span className="mt-1 block text-xs text-muted">
                    For payments not tied to a scheduled bill. A scheduled debt payment goes under Bill.
                  </span>
                </Field>
              ) : null}
              <p className="text-xs text-muted">Linking a bill marks it paid so the forecast stops counting it as still due.</p>
            </div>
          ) : null}
        </div>
      ) : null}

      <div className="space-y-2">
        <label className="btn-glass flex min-h-11 cursor-pointer items-center gap-3 rounded-xl px-3 text-sm text-ink">
          <input
            type="checkbox"
            checked={makeRule}
            onChange={(e) => setMakeRule(e.target.checked)}
            className="h-5 w-5 shrink-0 accent-[var(--accent)]"
          />
          <span className="min-w-0 truncate">Always do this for {merchantName}</span>
        </label>
        {makeRule ? (
          <Field label="Match bank descriptions containing">
            <input
              className={inputClass}
              value={pattern}
              onChange={(e) => setPattern(e.target.value)}
              maxLength={120}
              autoComplete="off"
              autoCapitalize="off"
              spellCheck={false}
              enterKeyHint="done"
            />
            <span className={cx('mt-1 block text-xs', patternOk ? 'text-muted' : 'text-warn')}>
              {patternOk
                ? 'Sets this category on future imports and on other open reviews that match. Not case-sensitive.'
                : `This text is not in “${t.description_raw}”, so it will not match this merchant.`}
            </span>
          </Field>
        ) : null}
      </div>

      {error ? (
        <Banner tone="danger" title={error.title}>
          {error.message}
        </Banner>
      ) : null}

      <div className="flex flex-col gap-2 sm:flex-row-reverse">
        <Button type="submit" variant="primary" disabled={busy} className="min-h-12 flex-1 text-base">
          {busy ? 'Saving…' : submitLabel}
        </Button>
        {onSkip ? (
          <Button variant="ghost" onClick={onSkip} disabled={busy} className="min-h-12 flex-1">
            Skip
          </Button>
        ) : null}
      </div>
    </form>
  );
}
