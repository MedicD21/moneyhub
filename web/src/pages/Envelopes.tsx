import { useState, type FormEvent } from 'react';
import { useView } from '../hooks/useView';
import type { VEnvelope, VEnvelopeMove, VRainyDaySuggestion } from '../types/db';
import { formatCurrency, formatDate } from '../lib/format';
import { amountToInputText, parseAmountCents, sanitizeAmountInput } from '../lib/money';
import { moveEnvelopeMoney } from '../lib/writes';
import { cx } from '../lib/cx';
import { Banner, Button, Card, Field, Money, PageHeader, Stat, inputClass } from '../components/ui';
import { QueryState } from '../components/QueryState';
import { Icon } from '../components/Icon';
import { useEntry } from '../components/EntryContext';

export default function Envelopes() {
  const { version } = useEntry();
  const envelopes = useView<VEnvelope>(`v_envelopes:${version}`, (sb) =>
    sb.from('v_envelopes').select('*').eq('is_active', true).order('kind', { ascending: false }),
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

  return (
    <>
      <PageHeader
        title="Envelopes"
        description="Virtual savings. No real money moves: an envelope only changes how much of your cash the forecast treats as spendable."
      />
      <QueryState state={envelopes} label="envelopes" empty="No envelopes yet." loadingLines={6}>
        {(rows) => (
          <div className="grid gap-4 md:grid-cols-2">
            {rows.map((e) => (
              <EnvelopeCard key={e.id} env={e} suggestion={e.kind === 'rainy_day' ? (suggestion.data?.[0] ?? null) : null} />
            ))}
          </div>
        )}
      </QueryState>

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

type Mode = 'in' | 'out';

function EnvelopeCard({ env, suggestion }: { env: VEnvelope; suggestion: VRainyDaySuggestion | null }) {
  const { bump } = useEntry();
  const locked = env.kind === 'locked_savings';
  const [mode, setMode] = useState<Mode | null>(null);
  const [amountText, setAmountText] = useState('');
  const [note, setNote] = useState('');
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  function open(next: Mode, prefill = '') {
    setMode(next);
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
    const dollars = cents / 100;
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

  const showSuggestion = !locked && suggestion !== null && suggestion.gap_to_floor > 0;

  return (
    <Card
      title={env.name}
      subtitle={
        locked
          ? 'Never used for bills. The forecast cannot draw on it.'
          : 'Held back from spending. A short pay period gets a suggested draw; you decide.'
      }
      action={locked ? <Icon name="lock" size={18} className="text-muted" /> : null}
    >
      <Stat label="Balance" value={<Money value={env.balance} />} emphasis />
      <div className="mt-1 text-xs text-muted">
        {env.last_move_date ? `Last move ${formatDate(env.last_move_date)}` : 'Nothing moved yet'}
      </div>

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
        <form onSubmit={(e) => void submit(e)} className="mt-3 space-y-3 rounded-xl border border-line p-3" noValidate>
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
              : locked
                ? 'This puts the money back into spendable cash and into the forecast.'
                : 'This puts the money back into spendable cash, which raises your safe-to-spend.'}
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
