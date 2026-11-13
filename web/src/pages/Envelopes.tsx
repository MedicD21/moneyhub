import { useState, type FormEvent } from 'react';
import { useView } from '../hooks/useView';
import type { VEnvelope, VEnvelopeMove, VRainyDaySuggestion } from '../types/db';
import { formatCurrency, formatDate } from '../lib/format';
import { amountToInputText, centsToDollars, parseAmountCents, sanitizeAmountInput } from '../lib/money';
import { createEnvelope, moveEnvelopeMoney, updateEnvelope } from '../lib/writes';
import { cx } from '../lib/cx';
import { Banner, Button, Card, CollapsibleCard, Field, Money, PageHeader, Stat, inputClass } from '../components/ui';
import { QueryState } from '../components/QueryState';
import { Icon } from '../components/Icon';
import { useEntry } from '../components/EntryContext';

const NAME_MAX = 60;

export default function Envelopes() {
  const { version } = useEntry();
  // rainy_day, locked_savings, then goal envelopes in the order they were created
  const envelopes = useView<VEnvelope>(`v_envelopes:all:${version}`, (sb) =>
    sb.from('v_envelopes').select('*').order('kind', { ascending: false }).order('created_at'),
  );
  const suggestion = useView<VRainyDaySuggestion>(`v_rainy_day_suggestion:${version}`, (sb) =>
    sb.from('v_rainy_day_suggestion').select('*').limit(1),
  );
  const moves = useView<VEnvelopeMove>(`v_envelope_moves:${version}`, (sb) =>
    sb
      .from('v_envelope_moves')
      .select('*')
      .order('move_date', { ascending: false })
      .order('created_at', { ascending: false })
      .limit(50),
  );
  const archived = (envelopes.data ?? []).filter((e) => !e.is_active);

  return (
    <>
      <PageHeader
        title="Envelopes"
        description="Virtual savings pots. No real money moves: an envelope only changes how much of your cash the forecast treats as spendable. Set-asides (per-paycheck reservations) live on the Paychecks page."
      />
      <QueryState
        state={envelopes}
        label="envelopes"
        empty="No envelopes yet."
        loadingLines={6}
        isEmpty={(rows) => !rows.some((e) => e.is_active)}
      >
        {(rows) => (
          <div className="grid gap-4 md:grid-cols-2">
            {rows
              .filter((e) => e.is_active)
              .map((e) => (
                <EnvelopeCard key={e.id} env={e} suggestion={e.kind === 'rainy_day' ? (suggestion.data?.[0] ?? null) : null} />
              ))}
          </div>
        )}
      </QueryState>

      <NewEnvelopeCard />

      {archived.length > 0 ? (
        <CollapsibleCard className="mt-4" title="Archived envelopes" meta={archived.length}>
          <ul className="-mx-4 divide-y divide-line sm:-mx-5">
            {archived.map((e) => (
              <ArchivedRow key={e.id} env={e} />
            ))}
          </ul>
        </CollapsibleCard>
      ) : null}

      <Card className="mt-4" title="Recent moves" subtitle="Newest first">
        <QueryState state={moves} label="envelope moves" empty="Nothing moved yet.">
          {(rows) => (
            <ul className="-mx-4 divide-y divide-line sm:-mx-5">
              {rows.map((m) => (
                <li key={m.id} className="flex items-start justify-between gap-3 px-4 py-3 sm:px-5">
                  <div className="min-w-0">
                    <div className="text-sm font-medium text-ink">
                      {m.amount > 0 ? 'Added to' : 'Moved out of'} {m.envelope_name}
                    </div>
                    <div className="mt-0.5 text-xs text-muted">
                      {formatDate(m.move_date)} · balance after {formatCurrency(m.balance_after)}
                    </div>
                    {m.note ? <div className="mt-0.5 text-xs text-muted">Note: {m.note}</div> : null}
                  </div>
                  <Money value={m.amount} signed showPlus className="shrink-0 text-sm font-semibold" />
                </li>
              ))}
            </ul>
          )}
        </QueryState>
      </Card>
    </>
  );
}

function NewEnvelopeCard() {
  const [open, setOpen] = useState(false);
  const [session, setSession] = useState(0);
  const [done, setDone] = useState<string | null>(null);
  return (
    <Card className="mt-4" title="New envelope" subtitle="A named savings pot, such as Vacation. It starts at $0; add money to it once it exists.">
      {done ? (
        <p role="status" className="mb-3 text-sm font-medium text-pos">
          {done}
        </p>
      ) : null}
      {open ? (
        <NewEnvelopeForm
          key={session}
          onCancel={() => setOpen(false)}
          onCreated={(name) => {
            setDone(`Created ${name}.`);
            setOpen(false);
            setSession((s) => s + 1);
          }}
        />
      ) : (
        <Button
          onClick={() => {
            setDone(null);
            setOpen(true);
          }}
        >
          <Icon name="plus" size={16} /> New envelope
        </Button>
      )}
    </Card>
  );
}

function NewEnvelopeForm({ onCancel, onCreated }: { onCancel: () => void; onCreated: (name: string) => void }) {
  const { bump } = useEntry();
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const res = await createEnvelope(name);
    setBusy(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    bump();
    onCreated(name.trim());
  }

  return (
    <form onSubmit={(e) => void submit(e)} className="space-y-3" noValidate>
      <Field label="Name">
        <input
          className={inputClass}
          value={name}
          onChange={(e) => setName(e.target.value)}
          maxLength={NAME_MAX}
          autoComplete="off"
          autoCapitalize="words"
          enterKeyHint="done"
          placeholder="e.g. Vacation"
          autoFocus
        />
      </Field>
      {error ? <Banner tone="danger" title="Not created">{error}</Banner> : null}
      <div className="flex gap-2">
        <Button type="submit" variant="primary" disabled={busy} className="min-h-11 flex-1">
          {busy ? 'Creating…' : 'Create envelope'}
        </Button>
        <Button onClick={onCancel} disabled={busy} className="min-h-11">
          Cancel
        </Button>
      </div>
    </form>
  );
}

function ArchivedRow({ env }: { env: VEnvelope }) {
  const { bump } = useEntry();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function restore() {
    setBusy(true);
    setError(null);
    const res = await updateEnvelope(env.id, env.name, true);
    setBusy(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    bump();
  }
  return (
    <li className="px-4 py-3 sm:px-5">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <div className="truncate text-sm font-medium text-ink">{env.name}</div>
          <div className="mt-0.5 text-xs text-muted">
            {env.last_move_date ? `Last move ${formatDate(env.last_move_date)}` : 'Never used'}
          </div>
        </div>
        <Button onClick={() => void restore()} disabled={busy} className="shrink-0">
          {busy ? 'Restoring…' : 'Restore'}
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

type Mode = 'in' | 'out';

function subtitleFor(env: VEnvelope): string {
  if (env.kind === 'locked_savings') return 'Never used for bills. The forecast cannot draw on it.';
  if (env.kind === 'rainy_day') return 'Held back from spending. A short pay period gets a suggested draw; you decide.';
  return 'Your savings pot. Like locked savings, the forecast never spends it or suggests a draw from it.';
}

function EnvelopeCard({ env, suggestion }: { env: VEnvelope; suggestion: VRainyDaySuggestion | null }) {
  const { bump } = useEntry();
  const locked = env.kind === 'locked_savings';
  const goal = env.kind === 'goal';
  const [mode, setMode] = useState<Mode | null>(null);
  const [editing, setEditing] = useState(false);
  const [amountText, setAmountText] = useState('');
  const [note, setNote] = useState('');
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  function open(next: Mode, prefill = '') {
    setMode(next);
    setEditing(false);
    setAmountText(prefill);
    setNote('');
    setConfirm(false);
    setError(null);
    setDone(null);
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!mode) return;
    const cents = parseAmountCents(amountText);
    if (cents === null) {
      setError('Enter an amount above $0.00.');
      return;
    }
    if (locked && mode === 'out' && !confirm) {
      setError('Tick the box to confirm you want to take money out of locked savings.');
      return;
    }
    setBusy(true);
    setError(null);
    const dollars = centsToDollars(cents);
    const res = await moveEnvelopeMoney(env.id, mode === 'in' ? dollars : -dollars, note.trim() || null);
    setBusy(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    setDone(`${mode === 'in' ? 'Added' : 'Moved out'} ${formatCurrency(dollars)}. New balance ${formatCurrency(res.data)}.`);
    setMode(null);
    setAmountText('');
    bump();
  }

  const showSuggestion = env.kind === 'rainy_day' && suggestion !== null && suggestion.gap_to_floor > 0;

  return (
    <Card
      title={env.name}
      subtitle={subtitleFor(env)}
      action={
        locked ? (
          <Icon name="lock" size={18} className="text-muted" />
        ) : goal ? (
          <button
            type="button"
            onClick={() => {
              setEditing((v) => !v);
              setMode(null);
              setDone(null);
            }}
            aria-expanded={editing}
            className="-my-2.5 inline-flex min-h-10 shrink-0 items-center gap-1 rounded-lg px-2 text-sm font-medium text-accent hover:bg-surface-2 focus-visible:outline-2 focus-visible:outline-accent"
          >
            <Icon name="edit" size={16} /> Edit
          </button>
        ) : null
      }
    >
      <Stat label="Balance" value={<Money value={env.balance} />} emphasis />
      <div className="mt-1 text-xs text-muted">
        {env.last_move_date ? `Last move ${formatDate(env.last_move_date)}` : 'Nothing moved yet'}
      </div>

      {editing ? <GoalEditForm env={env} onDone={() => setEditing(false)} /> : null}

      {showSuggestion ? (
        <div className="mt-3">
          <Banner tone="warn" title="This pay period is short">
            Cash is projected to reach {formatCurrency(suggestion.binding_balance)} around {formatDate(suggestion.binding_date, 'short')}, {formatCurrency(suggestion.gap_to_floor)} below your {formatCurrency(suggestion.low_balance_floor)} minimum.
            {suggestion.suggested_draw > 0 ? (
              <>
                {' '}
                Suggested draw: <strong>{formatCurrency(suggestion.suggested_draw)}</strong>
                {suggestion.remaining_gap > 0 ? `, leaving ${formatCurrency(suggestion.remaining_gap)} still short.` : ', which closes the gap.'}
              </>
            ) : (
              ' The fund is empty, so there is nothing to draw.'
            )}
          </Banner>
          {suggestion.suggested_draw > 0 && mode !== 'out' ? (
            <div className="mt-2">
              <Button onClick={() => open('out', amountToInputText(suggestion.suggested_draw))} variant="primary">
                Use the suggested {formatCurrency(suggestion.suggested_draw)}
              </Button>
            </div>
          ) : null}
        </div>
      ) : null}

      <div className="mt-3 flex flex-wrap gap-2">
        <Button onClick={() => open('in')} disabled={busy}>
          <Icon name="plus" size={16} /> Add money
        </Button>
        <Button onClick={() => open('out')} disabled={busy || env.balance <= 0}>
          Move out
        </Button>
      </div>

      {done ? (
        <p role="status" className="mt-3 text-sm font-medium text-pos">
          {done}
        </p>
      ) : null}

      {mode ? (
        <form onSubmit={(e) => void submit(e)} className="page-enter mt-3 space-y-3 rounded-2xl border border-line bg-surface-2 p-3" noValidate>
          <div className="text-sm font-semibold text-ink">{mode === 'in' ? `Add money to ${env.name}` : `Move money out of ${env.name}`}</div>
          <Field label="Amount">
            <input
              className={cx(inputClass, 'text-lg! font-semibold tabular-nums')}
              value={amountText}
              onChange={(e) => setAmountText(sanitizeAmountInput(e.target.value))}
              inputMode="decimal"
              pattern="[0-9]*[.,]?[0-9]*"
              autoComplete="off"
              enterKeyHint="done"
              placeholder="0.00"
              aria-label="Amount in dollars"
              autoFocus
            />
          </Field>
          <Field label="Note (optional)">
            <input className={inputClass} value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} autoComplete="off" />
          </Field>
          <p className="text-xs text-muted">
            {mode === 'in'
              ? 'This lowers the cash the forecast treats as spendable. Envelopes can hold only cash that set-asides are not already holding.'
              : env.kind === 'rainy_day'
                ? 'This puts the money back into spendable cash, which raises your safe-to-spend.'
                : 'This puts the money back into spendable cash and into the forecast.'}
          </p>
          {locked && mode === 'out' ? (
            <label className="flex min-h-10 cursor-pointer items-center gap-3 text-sm text-ink">
              <input type="checkbox" checked={confirm} onChange={(e) => setConfirm(e.target.checked)} className="h-5 w-5 accent-[var(--accent)]" />
              I’m sure I want to take this out of locked savings
            </label>
          ) : null}
          {error ? <Banner tone="danger" title="Not moved">{error}</Banner> : null}
          <div className="flex gap-2">
            <Button type="submit" variant="primary" disabled={busy} className="min-h-11 flex-1">
              {busy ? 'Saving…' : mode === 'in' ? 'Add' : 'Move out'}
            </Button>
            <Button onClick={() => setMode(null)} disabled={busy} className="min-h-11">
              Cancel
            </Button>
          </div>
        </form>
      ) : null}
    </Card>
  );
}

/** Rename or archive a goal envelope. Archiving needs a $0 balance (the database enforces it too). */
function GoalEditForm({ env, onDone }: { env: VEnvelope; onDone: () => void }) {
  const { bump } = useEntry();
  const [name, setName] = useState(env.name);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const canArchive = env.balance === 0;

  async function save(isActive: boolean) {
    setBusy(true);
    setError(null);
    const res = await updateEnvelope(env.id, isActive ? name : env.name, isActive);
    setBusy(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    bump();
    onDone();
  }

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        void save(true);
      }}
      className="page-enter mt-3 space-y-3 rounded-2xl border border-line bg-surface-2 p-3"
      noValidate
    >
      <Field label="Name">
        <input
          className={inputClass}
          value={name}
          onChange={(e) => setName(e.target.value)}
          maxLength={NAME_MAX}
          autoComplete="off"
          autoCapitalize="words"
          enterKeyHint="done"
        />
      </Field>
      {error ? <Banner tone="danger" title="Not saved">{error}</Banner> : null}
      <div className="flex flex-wrap gap-2">
        <Button type="submit" variant="primary" disabled={busy} className="min-h-11 flex-1">
          {busy ? 'Saving…' : 'Save name'}
        </Button>
        <Button onClick={() => void save(false)} disabled={busy || !canArchive} className="min-h-11">
          Archive
        </Button>
      </div>
      <p className="text-xs text-muted">
        {canArchive
          ? 'Archiving hides the envelope. Its history stays, and you can restore it later.'
          : 'To archive this envelope, move its money out first.'}
      </p>
    </form>
  );
}
