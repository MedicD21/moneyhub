import { useState, type FormEvent } from 'react';
import { useView } from '../hooks/useView';
import { useEntry } from './EntryContext';
import type { CategoryRow, VAppInfo, VSetAside } from '../types/db';
import { formatCurrency, todayLocal } from '../lib/format';
import { amountToInputText, centsToDollars, parseCentsAllowZero, sanitizeAmountInput } from '../lib/money';
import { createSetAside, updateSetAside, type SetAsideInput } from '../lib/writes';
import { cx } from '../lib/cx';
import { Badge, Banner, Button, Field, Meter, Money, inputClass } from './ui';
import { Icon } from './Icon';
import { QueryState } from './QueryState';

const NAME_MAX = 60;

/** A row's stored settings, passed back unchanged (pause / resume change only is_active). */
function inputFromRow(r: VSetAside): SetAsideInput {
  return {
    name: r.name,
    perPaycheck: r.per_paycheck,
    cap: r.cap,
    startDate: r.start_date,
    openingBalance: r.opening_balance,
    categoryId: r.category_id,
  };
}

/**
 * Set-asides: per-paycheck reservations with a rollover balance (public.set_asides). Not envelopes.
 * Every number shown comes from v_set_asides; the forms only send names, amounts and ids.
 */
export function SetAsidesSection() {
  const { version } = useEntry();
  const rows = useView<VSetAside>(`v_set_asides:all:${version}`, (sb) =>
    sb.from('v_set_asides').select('*').order('is_active', { ascending: false }).order('name'),
  );
  const [form, setForm] = useState<{ editing: VSetAside | null; session: number } | null>(null);
  const [done, setDone] = useState<string | null>(null);

  const openForm = (editing: VSetAside | null) => {
    setDone(null);
    setForm((f) => ({ editing, session: (f?.session ?? 0) + 1 }));
  };

  return (
    <section aria-labelledby="set-asides-title" className="mb-4 rounded-2xl border border-line bg-surface p-4 sm:p-5">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h2 id="set-asides-title" className="text-sm font-semibold text-ink">
            Set-asides
          </h2>
          <p className="mt-0.5 text-xs text-muted">
            Money held back from each paycheck. Balances roll over up to the cap, and spending in the linked category
            draws them down. Not the same as envelopes.
          </p>
        </div>
        {!form ? (
          <Button onClick={() => openForm(null)} className="shrink-0">
            <Icon name="plus" size={16} /> New
          </Button>
        ) : null}
      </div>

      {done ? (
        <p role="status" className="mt-3 text-sm font-medium text-pos">
          {done}
        </p>
      ) : null}

      {form ? (
        <SetAsideForm
          key={form.session}
          editing={form.editing}
          onClose={(message) => {
            setForm(null);
            if (message) setDone(message);
          }}
        />
      ) : null}

      <div className="mt-3">
        <QueryState state={rows} label="set-asides" empty="No set-asides yet. Use New to hold some of each paycheck back for something.">
          {(list) => (
            <ul className="grid gap-3 sm:grid-cols-2">
              {list.map((r) => (
                <SetAsideItem key={r.id} r={r} onEdit={() => openForm(r)} onChanged={setDone} />
              ))}
            </ul>
          )}
        </QueryState>
      </div>
    </section>
  );
}

function SetAsideItem({ r, onEdit, onChanged }: { r: VSetAside; onEdit: () => void; onChanged: (message: string) => void }) {
  const { bump } = useEntry();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Bar width only (chart scaling) from the view's balance and cap.
  const pct = r.cap && r.cap > 0 ? Math.min(Math.max(r.balance / r.cap, 0), 1) : null;

  async function setActive(isActive: boolean) {
    setBusy(true);
    setError(null);
    const res = await updateSetAside(r.id, inputFromRow(r), isActive);
    setBusy(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    bump();
    onChanged(isActive ? `Resumed ${r.name}.` : `Paused ${r.name}.`);
  }

  return (
    <li className={cx('rounded-xl border border-line bg-surface-2 p-3', !r.is_active && 'opacity-80')}>
      <div className="flex items-baseline justify-between gap-3">
        <span className="flex min-w-0 flex-wrap items-center gap-1.5">
          <span className="truncate text-sm font-medium text-ink">{r.name}</span>
          {!r.is_active ? <Badge tone="muted">Paused</Badge> : null}
        </span>
        <span className={cx('text-base font-semibold tabular-nums', r.balance < 0 ? 'text-danger' : 'text-ink')}>
          <Money value={r.balance} />
        </span>
      </div>
      {pct !== null && r.is_active ? (
        <Meter percent={pct * 100} label={`${Math.round(pct * 100)}% of cap`} className="mt-2" />
      ) : null}
      <p className="mt-1.5 text-xs text-muted">
        {formatCurrency(r.per_paycheck)} per paycheck
        {r.cap !== null ? ` · cap ${formatCurrency(r.cap)}${r.at_cap ? ' (full)' : ''}` : ' · no cap'}
        {r.category_name ? ` · draws from ${r.category_name}` : ''}
      </p>
      {!r.is_active ? (
        <p className="mt-0.5 text-xs text-muted">Paused: takes nothing from paychecks and no longer holds back its balance.</p>
      ) : null}
      <div className="mt-2 flex flex-wrap gap-2">
        <Button onClick={onEdit} disabled={busy} variant="ghost" className="-ml-2">
          <Icon name="edit" size={16} /> Edit
        </Button>
        <Button onClick={() => void setActive(!r.is_active)} disabled={busy} variant="ghost">
          {busy ? 'Saving…' : r.is_active ? 'Pause' : 'Resume'}
        </Button>
      </div>
      {error ? (
        <p role="alert" className="mt-1 text-xs text-danger">
          {error}
        </p>
      ) : null}
    </li>
  );
}

function moneyField(value: number | null): string {
  return value === null ? '' : amountToInputText(value);
}

function SetAsideForm({ editing, onClose }: { editing: VSetAside | null; onClose: (message?: string) => void }) {
  const { bump } = useEntry();
  const appInfo = useView<VAppInfo>('v_app_info', (sb) => sb.from('v_app_info').select('*').limit(1));
  const categories = useView<CategoryRow>('categories', (sb) => sb.from('categories').select('*').order('name'));

  const [name, setName] = useState(editing?.name ?? '');
  const [perText, setPerText] = useState(editing ? moneyField(editing.per_paycheck) : '');
  const [capText, setCapText] = useState(editing ? moneyField(editing.cap) : '');
  const [startDate, setStartDate] = useState(editing?.start_date ?? '');
  // A negative starting balance (only possible from the chat) is kept as stored; the field cannot show a sign.
  const negativeOpening = editing !== null && editing.opening_balance < 0;
  const [openingText, setOpeningText] = useState(editing && !negativeOpening ? moneyField(editing.opening_balance) : '');
  const [categoryId, setCategoryId] = useState(editing?.category_id ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const today = appInfo.data?.[0]?.today ?? todayLocal();
  const effectiveStart = startDate || today;
  const pickable = (categories.data ?? []).filter((c) => c.kind === 'expense' || c.id === categoryId);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    const perCents = parseCentsAllowZero(perText);
    if (perCents === null) {
      setError('Enter the amount per paycheck (0 is allowed).');
      return;
    }
    const capCents = capText.trim() === '' ? null : parseCentsAllowZero(capText);
    if (capText.trim() !== '' && capCents === null) {
      setError('Enter a cap like 300 or 300.00, or leave it empty for no cap.');
      return;
    }
    const openingCents = openingText.trim() === '' ? 0 : parseCentsAllowZero(openingText);
    if (openingCents === null) {
      setError('Enter the amount already saved, or leave it empty for $0.');
      return;
    }
    const input: SetAsideInput = {
      name,
      perPaycheck: centsToDollars(perCents),
      cap: capCents === null ? null : centsToDollars(capCents),
      startDate: effectiveStart,
      openingBalance: negativeOpening && editing ? editing.opening_balance : centsToDollars(openingCents),
      categoryId: categoryId || null,
    };
    setBusy(true);
    const res = editing ? await updateSetAside(editing.id, input, editing.is_active) : await createSetAside(input);
    setBusy(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    bump();
    onClose(editing ? `Saved ${name.trim()}.` : `Created ${name.trim()}.`);
  }

  const moneyInput = (value: string, onChange: (v: string) => void, label: string, placeholder = '0.00') => (
    <input
      className={cx(inputClass, 'tabular-nums')}
      value={value}
      onChange={(e) => onChange(sanitizeAmountInput(e.target.value))}
      inputMode="decimal"
      pattern="[0-9]*[.,]?[0-9]*"
      autoComplete="off"
      enterKeyHint="next"
      placeholder={placeholder}
      aria-label={label}
    />
  );

  return (
    <form onSubmit={(e) => void submit(e)} className="mt-3 space-y-3 rounded-xl border border-line p-3" noValidate>
      <div className="text-sm font-semibold text-ink">{editing ? `Edit ${editing.name}` : 'New set-aside'}</div>
      <Field label="Name">
        <input
          className={inputClass}
          value={name}
          onChange={(e) => setName(e.target.value)}
          maxLength={NAME_MAX}
          autoComplete="off"
          autoCapitalize="words"
          enterKeyHint="next"
          placeholder="e.g. Car repairs"
          autoFocus={!editing}
        />
      </Field>
      <div className="grid grid-cols-2 gap-3">
        <Field label="Per paycheck">{moneyInput(perText, setPerText, 'Amount per paycheck in dollars')}</Field>
        <Field label="Cap (optional)">{moneyInput(capText, setCapText, 'Cap in dollars', 'No cap')}</Field>
      </div>
      <div className="grid grid-cols-2 gap-3">
        <Field label="Starts">
          <input type="date" className={inputClass} value={effectiveStart} onChange={(e) => setStartDate(e.target.value)} />
        </Field>
        {negativeOpening && editing ? (
          <div className="flex min-w-0 flex-col gap-1 text-xs font-medium text-muted">
            Already saved
            <span className="flex min-h-11 items-center text-sm text-ink sm:min-h-10">
              <Money value={editing.opening_balance} />
            </span>
          </div>
        ) : (
          <Field label="Already saved">{moneyInput(openingText, setOpeningText, 'Amount already saved in dollars')}</Field>
        )}
      </div>
      <p className="-mt-1 text-xs text-muted">Starts: contributions begin with the paycheck that covers this date.</p>
      <Field label="Category (optional)">
        <select className={inputClass} value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
          <option value="">{categories.loading ? 'Loading…' : 'No category'}</option>
          {pickable.map((c) => (
            <option key={c.id} value={c.id}>
              {c.parent_name ? `${c.parent_name} › ${c.name}` : c.name}
            </option>
          ))}
        </select>
        <span className="mt-1 block font-normal">
          Linking a category makes untagged spending in it draw from this set-aside automatically.
        </span>
      </Field>
      {error ? <Banner tone="danger" title="Not saved">{error}</Banner> : null}
      <div className="flex gap-2">
        <Button type="submit" variant="primary" disabled={busy} className="min-h-11 flex-1">
          {busy ? 'Saving…' : editing ? 'Save changes' : 'Create set-aside'}
        </Button>
        <Button onClick={() => onClose()} disabled={busy} className="min-h-11">
          Cancel
        </Button>
      </div>
      {editing ? (
        <p className="text-xs text-muted">
          Changing the amount, start date or starting balance recalculates the balance from that date.
        </p>
      ) : null}
    </form>
  );
}
