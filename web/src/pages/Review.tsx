import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useView } from '../hooks/useView';
import type { VReviewQueue } from '../types/db';
import { formatCount, formatDate } from '../lib/format';
import { Badge, Banner, Button, Card, Money, PageHeader } from '../components/ui';
import { QueryState } from '../components/QueryState';
import { ClassifyForm, type ClassifyOutcome } from '../components/ClassifyForm';
import { Icon } from '../components/Icon';
import { useEntry } from '../components/EntryContext';
import { cx } from '../lib/cx';

type Status = { tone: 'info' | 'danger'; title: string; body?: string };

/**
 * Review inbox: transactions Claude flagged (v_review_queue), one at a time. Saving resolves the row
 * through review_transaction; the list and the nav count reload from the database afterwards.
 */
export default function Review() {
  const { version } = useEntry();
  const queue = useView<VReviewQueue>(`v_review_queue:${version}`, (sb) =>
    sb
      .from('v_review_queue')
      .select('*')
      .order('txn_date', { ascending: false })
      .order('created_at', { ascending: false })
      .order('id'),
  );
  const [focusId, setFocusId] = useState<string | null>(null);
  const [skipped, setSkipped] = useState<string[]>([]);
  const [status, setStatus] = useState<Status | null>(null);

  function saved(merchant: string, outcome: ClassifyOutcome) {
    setFocusId(null);
    if (outcome.ruleError) {
      setStatus({ tone: 'danger', title: `Saved ${merchant}, but the rule was not`, body: outcome.ruleError });
    } else if (outcome.ruleCount !== null) {
      setStatus({
        tone: 'info',
        title: `Saved ${merchant} and the rule`,
        body:
          outcome.ruleCount > 0
            ? `The rule also sorted ${formatCount(outcome.ruleCount)} more open review${outcome.ruleCount === 1 ? '' : 's'}.`
            : 'Future imports that match will get this category.',
      });
    } else {
      setStatus({ tone: 'info', title: `Saved ${merchant}` });
    }
  }

  return (
    <>
      <PageHeader title="Review" description="Transactions Claude flagged. Answer the question, pick a category, move on." />

      <div aria-live="polite" className="mb-4 empty:hidden">
        {status ? (
          <Banner tone={status.tone} title={status.title} icon={status.tone === 'info' ? 'check' : undefined}>
            {status.body}
          </Banner>
        ) : null}
      </div>

      <QueryState state={queue} label="review queue" loadingLines={8} empty={<EmptyInbox />}>
        {(rows) => {
          const open = rows.filter((r) => !skipped.includes(r.id));
          const current = open.find((r) => r.id === focusId) ?? open[0] ?? null;
          if (!current) {
            return (
              <Card>
                <div className="flex flex-col items-start gap-3">
                  <p className="text-sm text-ink">
                    You skipped {formatCount(rows.length)} transaction{rows.length === 1 ? '' : 's'}.
                  </p>
                  <Button variant="primary" onClick={() => setSkipped([])}>
                    Go through skipped ones
                  </Button>
                </div>
              </Card>
            );
          }
          const upNext = open.filter((r) => r.id !== current.id);
          const merchant = current.merchant ?? current.description_raw;
          return (
            <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem]">
              <Card
                title={`${formatCount(rows.length)} to review`}
                subtitle={skipped.length > 0 ? `${formatCount(skipped.length)} skipped` : undefined}
              >
                <ClassifyForm
                  key={current.id}
                  t={current}
                  submitLabel="Save and next"
                  onSaved={(o) => saved(merchant, o)}
                  onSkip={() => {
                    setStatus(null);
                    setFocusId(null);
                    setSkipped((s) => [...s, current.id]);
                  }}
                />
              </Card>

              {upNext.length > 0 ? (
                <Card title="Up next">
                  <ul className="-mx-4 divide-y divide-line sm:-mx-5">
                    {upNext.map((r) => (
                      <li key={r.id}>
                        <button
                          type="button"
                          onClick={() => {
                            setStatus(null);
                            setFocusId(r.id);
                          }}
                          className="flex min-h-12 w-full items-center justify-between gap-3 px-4 py-2 text-left transition-colors hover:bg-surface-2 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent-bright sm:px-5"
                        >
                          <span className="min-w-0">
                            <span className="flex items-center gap-1.5">
                              <span className="truncate text-sm font-medium text-ink">{r.merchant ?? r.description_raw}</span>
                              {r.status === 'pending' ? <Badge tone="warn">Pending</Badge> : null}
                            </span>
                            <span className="block text-xs text-muted">{formatDate(r.txn_date)}</span>
                          </span>
                          <Money value={r.amount} signed showPlus className="shrink-0 text-sm font-semibold" />
                        </button>
                      </li>
                    ))}
                  </ul>
                </Card>
              ) : null}
            </div>
          );
        }}
      </QueryState>
    </>
  );
}

function EmptyInbox() {
  const { openAdd } = useEntry();
  return (
    <div className="flex flex-col items-center gap-3">
      <span className={cx('grid h-10 w-10 place-items-center rounded-xl border border-line text-accent-bright')} aria-hidden="true">
        <Icon name="check" size={20} />
      </span>
      <p className="text-ink">Nothing to review.</p>
      <p>When Claude flags an import, it shows up here.</p>
      <div className="flex flex-wrap justify-center gap-2">
        <Button variant="primary" onClick={openAdd}>
          <Icon name="plus" size={16} /> Add a transaction
        </Button>
        <Link
          to="/transactions"
          className="btn-glass inline-flex min-h-10 items-center rounded-xl px-3.5 text-sm font-medium text-ink focus-visible:outline-2 focus-visible:outline-accent-bright"
        >
          Browse transactions
        </Link>
      </div>
    </div>
  );
}
