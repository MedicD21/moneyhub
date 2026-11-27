import { useState } from 'react';
import { useView } from '../hooks/useView';
import { useEntry } from '../components/EntryContext';
import { Badge, Banner, Button, Card, Field, Money, PageHeader, Row, inputClass } from '../components/ui';
import { ErrorState, LoadingState } from '../components/QueryState';
import { shortfallPlanForecast } from '../lib/reads';
import { saveShortfallPlan } from '../lib/writes';
import {
  addHours,
  draftToEntries,
  entriesToDraft,
  sameEntries,
  sanitizeHoursInput,
  type PlannerDraft,
  type PlannerDraftRow,
} from '../lib/planner';
import { sanitizeAmountInput } from '../lib/money';
import { formatCurrency, formatDate, formatDateRange } from '../lib/format';
import { cx } from '../lib/cx';
import type { ShortfallPeriod, ShortfallPlanResult } from '../types/db';

const EMPTY_ROW: PlannerDraftRow = { ot: '', spend: '' };

function hoursText(hours: number): string {
  return `${hours} ${hours === 1 ? 'hour' : 'hours'}`;
}

function savedAtText(iso: string | null): string {
  if (!iso) return 'Not saved yet';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return 'Saved';
  return `Saved ${new Intl.DateTimeFormat('en-US', { dateStyle: 'medium', timeStyle: 'short' }).format(d)}`;
}

export default function Planner() {
  const { version } = useEntry();
  const saved = useView<ShortfallPlanResult>(`planner:saved:${version}`, (sb, signal) => shortfallPlanForecast(sb, null, signal));
  const base = saved.data?.[0];
  return (
    <>
      <PageHeader
        title="Planner"
        description="Plan extra overtime and spending money for each paycheck and see what it does to your forecast."
        actions={<Badge tone="muted">Plan only</Badge>}
      />
      {saved.error ? (
        <ErrorState label="the planner" message={saved.error} onRetry={saved.reload} />
      ) : !base ? (
        <LoadingState label="your paychecks" lines={8} />
      ) : (
        <PlannerEditor key={`${version}:${base.plan_summary.saved_at ?? 'none'}`} saved={base} version={version} />
      )}
    </>
  );
}

function PlannerEditor({ saved, version }: { saved: ShortfallPlanResult; version: number }) {
  const { bump } = useEntry();
  const savedEntries = saved.plan_summary.saved_plan;
  const [draft, setDraft] = useState<PlannerDraft>(() => entriesToDraft(savedEntries));
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const parsed = draftToEntries(draft);
  const changed = parsed.error !== null || !sameEntries(parsed.entries, savedEntries);
  const scenario = useView<ShortfallPlanResult>(
    parsed.error === null && changed ? `planner:${version}:${JSON.stringify(parsed.entries)}` : null,
    (sb, signal) => shortfallPlanForecast(sb, parsed.entries, signal),
    400,
  );
  const result = !changed ? saved : (scenario.data?.[0] ?? saved);
  const summary = result.plan_summary;
  const busy = changed && parsed.error === null && scenario.loading;

  const setRow = (date: string, next: PlannerDraftRow) => {
    setMessage(null);
    setDraft((d) => ({ ...d, [date]: next }));
  };
  const applyAll = () => {
    setMessage(null);
    setDraft((d) => {
      const next = { ...d };
      for (const p of result.plan_periods) {
        if (p.suggested_hours && p.suggested_hours > 0) {
          const row = next[p.pay_date] ?? EMPTY_ROW;
          next[p.pay_date] = { ...row, ot: addHours(row.ot, p.suggested_hours) };
        }
      }
      return next;
    });
  };
  const save = () => {
    if (parsed.error !== null) return;
    setSaving(true);
    setMessage(null);
    void saveShortfallPlan(parsed.entries).then((r) => {
      if (r.ok) {
        bump();
      } else {
        setSaving(false);
        setMessage(r.error);
      }
    });
  };

  return (
    <div className="grid gap-5">
      <Card
        title="Where this leaves you"
        subtitle={`Overtime is estimated at ${formatCurrency(summary.extra_hour_net)} net per hour. When a real paycheck amount is entered it replaces the estimate.`}
      >
        <div aria-busy={busy} className={cx(busy && 'opacity-60 transition-opacity')}>
          <Row label="Lowest balance with this plan">
            <Money value={summary.lowest_balance} className={cx((summary.lowest_balance ?? 0) < summary.floor && 'text-danger')} />
            {summary.lowest_date ? <span className="text-muted"> on {formatDate(summary.lowest_date, 'short')}</span> : null}
          </Row>
          <Row label="Without a plan">
            <Money value={summary.baseline_lowest_balance} />
            {summary.baseline_lowest_date ? <span className="text-muted"> on {formatDate(summary.baseline_lowest_date, 'short')}</span> : null}
          </Row>
          <Row label="Planned overtime">
            {hoursText(summary.hours_planned)} <span className="text-muted">(about </span>
            <Money value={summary.ot_net_planned} />
            <span className="text-muted"> net)</span>
          </Row>
          <Row label="Planned spending money">
            <Money value={summary.spend_planned} />
          </Row>
          <Row label="Overtime still needed" strong>
            {summary.suggested_hours_total > 0 ? (
              <>
                {hoursText(summary.suggested_hours_total)} <span className="text-muted">(about </span>
                <Money value={summary.suggested_net_total} />
                <span className="text-muted"> net)</span>
              </>
            ) : (
              'None'
            )}
          </Row>
        </div>
        {summary.unfixable_shortfall > 0 ? (
          <div className="mt-3">
            <Banner tone="warn" title={`${formatCurrency(summary.unfixable_shortfall)} can't be fixed with overtime`}>
              That dip falls in a pay period that has already started, and the paycheck that would cover it is already paid.
              It has to be covered another way, for example a transfer into your account.
            </Banner>
          </div>
        ) : null}
        <div className="mt-4 flex flex-wrap items-center gap-2">
          <Button variant="primary" onClick={save} disabled={!changed || parsed.error !== null || saving}>
            {saving ? 'Saving…' : 'Save plan'}
          </Button>
          <Button onClick={applyAll} disabled={summary.suggested_hours_total === 0 || parsed.error !== null}>
            Use suggested hours
          </Button>
          <Button variant="ghost" onClick={() => setDraft(entriesToDraft(savedEntries))} disabled={!changed}>
            Undo changes
          </Button>
          <Button variant="ghost" onClick={() => setDraft({})} disabled={Object.keys(draft).length === 0}>
            Clear plan
          </Button>
        </div>
        <p className="mt-2 text-xs text-muted" role="status">
          {parsed.error ?? message ?? (changed ? 'Unsaved changes' : savedAtText(summary.saved_at))}
        </p>
        {scenario.error ? <p className="mt-2 text-xs text-danger">{scenario.error}</p> : null}
      </Card>

      <ul className={cx('grid list-none gap-4 p-0', busy && 'opacity-60 transition-opacity')} aria-busy={busy}>
        {result.plan_periods.map((p) => (
          <li key={p.pay_date}>
            <PaycheckCard p={p} row={draft[p.pay_date] ?? EMPTY_ROW} onChange={(next) => setRow(p.pay_date, next)} />
          </li>
        ))}
      </ul>

      <p className="text-xs text-muted">
        Spending money is held back at the start of that pay period, so the plan errs on the cautious side. The forecast
        otherwise covers scheduled bills and payments only, not groceries, gas or dining. Nothing here changes your Dashboard
        or your real forecast.
      </p>
    </div>
  );
}

function statusBadge(p: ShortfallPeriod) {
  if (p.status === 'received') return <Badge tone="ok">Paid</Badge>;
  if (p.status === 'actual') return <Badge tone="accent">Actual amount entered</Badge>;
  if (p.status === 'open') return <Badge tone="muted">Upcoming</Badge>;
  return <Badge tone="muted">Past</Badge>;
}

function PaycheckCard({ p, row, onChange }: { p: ShortfallPeriod; row: PlannerDraftRow; onChange: (next: PlannerDraftRow) => void }) {
  const short = p.shortfall > 0;
  const otDisabled = !p.ot_editable;
  return (
    <Card
      title={`Paycheck ${formatDate(p.pay_date, 'weekday')}`}
      subtitle={`Pays for work ${formatDateRange(p.work_start, p.work_end)} · ${formatCurrency(p.income_amount)}`}
      action={statusBadge(p)}
      tone={short ? 'danger' : 'default'}
    >
      <div className="grid gap-3 sm:grid-cols-2">
        <Field label={`Extra overtime hours worked ${formatDateRange(p.work_start, p.work_end)}`}>
          <input
            className={inputClass}
            inputMode="decimal"
            autoComplete="off"
            placeholder="0"
            value={row.ot}
            disabled={otDisabled}
            onChange={(e) => onChange({ ...row, ot: sanitizeHoursInput(e.target.value) })}
          />
          <span className="font-normal">
            {otDisabled
              ? p.status === 'actual'
                ? 'The real paycheck amount is entered, so it already includes any overtime.'
                : 'Already paid, so overtime can no longer be added.'
              : p.ot_net > 0
                ? `About ${formatCurrency(p.ot_net)} net added to this paycheck`
                : 'Estimated net pay is added to this paycheck'}
          </span>
        </Field>
        <Field label="Spending money (food, gas…)">
          <input
            className={inputClass}
            inputMode="decimal"
            autoComplete="off"
            placeholder="0.00"
            value={row.spend}
            disabled={!p.spend_editable}
            onChange={(e) => onChange({ ...row, spend: sanitizeAmountInput(e.target.value) })}
          />
          <span className="font-normal">
            {p.spend_editable
              ? `Held back for ${formatDateRange(p.pay_date, p.period_end)}, the days until your next paycheck`
              : 'This pay period is over'}
          </span>
        </Field>
      </div>
      {p.ot_replaced ? (
        <p className="mt-2 text-xs text-warn">The overtime you typed for this paycheck is ignored: the paycheck is paid or its real amount is entered.</p>
      ) : null}
      <div className="mt-3">
        <Row label="Lowest balance this period">
          <Money value={p.low_balance} className={cx(short && 'text-danger')} />
          <span className="text-muted"> on {formatDate(p.low_date, 'short')}</span>
        </Row>
        {p.spend_room > 0 ? (
          <Row label="Room to spend from here">
            <Money value={p.spend_room} />
          </Row>
        ) : null}
      </div>
      {p.suggested_hours && p.suggested_hours > 0 ? (
        <div className="mt-3 flex flex-wrap items-center justify-between gap-2 rounded-xl border border-warn-line bg-warn-bg px-3 py-2 text-sm text-warn">
          <span>
            Suggested: {hoursText(p.suggested_hours)} more
            {p.suggested_net !== null ? ` (about ${formatCurrency(p.suggested_net)} net)` : ''}
          </span>
          <Button onClick={() => onChange({ ...row, ot: addHours(row.ot, p.suggested_hours ?? 0) })}>Add</Button>
        </div>
      ) : null}
      {p.unfixable_shortfall > 0 ? (
        <p className="mt-3 text-sm text-warn">
          {formatCurrency(p.unfixable_shortfall)} short here, and overtime can't cover it because this paycheck is already paid.
        </p>
      ) : null}
    </Card>
  );
}
