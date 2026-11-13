import { useState } from 'react';
import { useView } from '../hooks/useView';
import { useQueryParams } from '../hooks/useParams';
import type { AccountRow, CategoryRow, VTag, VTransaction, VTransactionMonth } from '../types/db';
import { formatCount, formatDate, isMonthStart } from '../lib/format';
import { Badge, Button, Card, Field, Money, PageHeader, inputClass } from '../components/ui';
import { cx } from '../lib/cx';
import { MonthSelect } from '../components/MonthControls';
import { QueryState } from '../components/QueryState';
import { Icon } from '../components/Icon';
import { useEntry } from '../components/EntryContext';
import { setTransactionCleared } from '../lib/writes';

const PAGE_SIZE = 50;

export default function Transactions() {
  const { params, set } = useQueryParams();
  const monthParam = params.get('month');
  const month = isMonthStart(monthParam) ? monthParam : '';
  const category = params.get('category') ?? '';
  const account = params.get('account') ?? '';
  const tag = params.get('tag') ?? '';
  const review = params.get('review') === '1';
  const unreconciled = params.get('unreconciled') === '1';
  const { version, openAdd } = useEntry();
  const page = Math.max(1, Number.parseInt(params.get('page') ?? '1', 10) || 1);
  const from = (page - 1) * PAGE_SIZE;
  const to = from + PAGE_SIZE - 1;

  const months = useView<VTransactionMonth>('v_transaction_months', (sb) =>
    sb.from('v_transaction_months').select('*').order('month', { ascending: false }),
  );
  const tags = useView<VTag>('v_tags', (sb) => sb.from('v_tags').select('*').order('tag'));
  const categories = useView<CategoryRow>('categories', (sb) => sb.from('categories').select('*').order('name'));
  const accounts = useView<AccountRow>('accounts', (sb) => sb.from('accounts').select('*').order('name'));

  const key = JSON.stringify({ month, category, account, tag, review, unreconciled, page, version });
  const txns = useView<VTransaction>(`v_transactions:${key}`, (sb) => {
    let q = sb.from('v_transactions').select('*', { count: 'exact' });
    if (month) q = q.eq('month', month);
    if (category === 'none') q = q.is('category_id', null);
    else if (category) q = q.eq('category_id', category);
    if (account) q = q.eq('account_id', account);
    if (tag) q = q.contains('tags', [tag]);
    if (review) q = q.eq('needs_review', true);
    if (unreconciled) q = q.eq('reconciled', false);
    return q
      .order('txn_date', { ascending: false })
      .order('created_at', { ascending: false })
      .order('id')
      .range(from, to);
  });

  const filtered = Boolean(month || category || account || tag || review || unreconciled);
  const total = txns.count;

  return (
    <>
      <PageHeader
        title="Transactions"
        description="Newest first. Negative amounts are money out."
        actions={
          <Button variant="primary" onClick={openAdd}>
            <Icon name="plus" size={16} /> Add
          </Button>
        }
      />

      <Card className="mb-4">
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
          <Field label="Month">
            {months.error ? (
              <FilterError onRetry={months.reload} />
            ) : (
              <MonthSelect
                months={withCurrent((months.data ?? []).map((m) => m.month), month)}
                counts={new Map((months.data ?? []).map((m) => [m.month, m.txn_count]))}
                value={month}
                onChange={(m) => set({ month: m })}
                allLabel={months.loading ? 'Loading…' : 'All months'}
              />
            )}
          </Field>
          <Field label="Category">
            {categories.error ? (
              <FilterError onRetry={categories.reload} />
            ) : (
              <select className={inputClass} value={category} onChange={(e) => set({ category: e.target.value })}>
                <option value="">{categories.loading ? 'Loading…' : 'All categories'}</option>
                <option value="none">Uncategorized</option>
                {(categories.data ?? []).map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.parent_name ? `${c.parent_name} › ${c.name}` : c.name}
                  </option>
                ))}
              </select>
            )}
          </Field>
          <Field label="Account">
            {accounts.error ? (
              <FilterError onRetry={accounts.reload} />
            ) : (
              <select className={inputClass} value={account} onChange={(e) => set({ account: e.target.value })}>
                <option value="">{accounts.loading ? 'Loading…' : 'All accounts'}</option>
                {(accounts.data ?? []).map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                    {a.is_active ? '' : ' (inactive)'}
                  </option>
                ))}
              </select>
            )}
          </Field>
          <Field label="Tag">
            {tags.error ? (
              <FilterError onRetry={tags.reload} />
            ) : (
              <select className={inputClass} value={tag} onChange={(e) => set({ tag: e.target.value })}>
                <option value="">{tags.loading ? 'Loading…' : (tags.data ?? []).length === 0 ? 'No tags yet' : 'All tags'}</option>
                {tag && !(tags.data ?? []).some((t) => t.tag === tag) ? <option value={tag}>#{tag}</option> : null}
                {(tags.data ?? []).map((t) => (
                  <option key={t.tag} value={t.tag}>
                    #{t.tag} ({formatCount(t.txn_count)})
                  </option>
                ))}
              </select>
            )}
          </Field>
          <div className="col-span-2 flex flex-wrap items-end gap-2 lg:col-span-1">
            <label className="flex min-h-11 flex-1 cursor-pointer items-center gap-2 rounded-lg border border-line px-3 text-sm whitespace-nowrap text-ink sm:min-h-10">
              <input
                type="checkbox"
                checked={review}
                onChange={(e) => set({ review: e.target.checked ? '1' : null })}
                className="h-5 w-5 shrink-0 accent-[var(--accent)]"
              />
              Needs review
            </label>
            <label className="flex min-h-11 flex-1 cursor-pointer items-center gap-2 rounded-lg border border-line px-3 text-sm whitespace-nowrap text-ink sm:min-h-10">
              <input
                type="checkbox"
                checked={unreconciled}
                onChange={(e) => set({ unreconciled: e.target.checked ? '1' : null })}
                className="h-5 w-5 shrink-0 accent-[var(--accent)]"
              />
              Not reconciled
            </label>
            {filtered ? (
              <Button
                variant="ghost"
                onClick={() => set({ month: null, category: null, account: null, tag: null, review: null, unreconciled: null })}
              >
                Clear
              </Button>
            ) : null}
          </div>
        </div>
      </Card>

      <Card
        title={total !== null ? `${formatCount(total)} transaction${total === 1 ? '' : 's'}` : 'Transactions'}
        subtitle={filtered ? 'Filtered' : undefined}
      >
        <QueryState
          state={txns}
          label="transactions"
          loadingLines={10}
          empty={
            page > 1 && (total ?? 0) > 0 ? (
              <>
                This page is past the end.{' '}
                <button type="button" className="font-medium text-accent underline" onClick={() => set({ page: null })}>
                  Go to the first page
                </button>
              </>
            ) : filtered ? (
              'No transactions match these filters.'
            ) : (
              'No transactions yet. Add one with the + button, or send Claude a screenshot to import.'
            )
          }
        >
          {(rows) => (
            <>
              <ul className="-mx-4 divide-y divide-line sm:-mx-5">
                {rows.map((t) => (
                  <TransactionRow key={t.id} t={t} />
                ))}
              </ul>
              <Pagination
                page={page}
                from={from}
                shown={rows.length}
                total={total}
                onPage={(p) => {
                  set({ page: p > 1 ? String(p) : null });
                  window.scrollTo({ top: 0 });
                }}
              />
            </>
          )}
        </QueryState>
      </Card>
    </>
  );
}

function FilterError({ onRetry }: { onRetry: () => void }) {
  return (
    <button type="button" onClick={onRetry} className={cx(inputClass, 'text-left text-danger')}>
      Couldn’t load · retry
    </button>
  );
}

/** Keep a selected month in the option list even if the view no longer has it (e.g. a stale link). */
function withCurrent(months: string[], current: string): string[] {
  return current && !months.includes(current) ? [current, ...months] : months;
}

function TransactionRow({ t }: { t: VTransaction }) {
  const { openEdit, bump } = useEntry();
  const title = t.merchant ?? t.description_raw;
  const manual = t.entry_source === 'manual';
  // Optimistic cleared state, keyed to the server value it was set against so a reload wins.
  const [override, setOverride] = useState<{ for: boolean; value: boolean } | null>(null);
  const [toggleError, setToggleError] = useState<string | null>(null);
  const cleared = override !== null && override.for === t.cleared ? override.value : t.cleared;

  async function toggleCleared(next: boolean) {
    setOverride({ for: t.cleared, value: next });
    setToggleError(null);
    const res = await setTransactionCleared(t.id, next);
    if (!res.ok) {
      setOverride(null);
      setToggleError(res.error);
      return;
    }
    bump();
  }
  return (
    <li className={cx('px-4 py-3 sm:px-5', t.needs_review && 'border-l-4 border-warn-line bg-warn-bg/60 pl-3 sm:pl-4')}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="truncate text-sm font-medium text-ink" title={t.description_raw}>
              {title}
            </span>
            {manual ? <Badge tone="accent">Manual</Badge> : t.status === 'pending' ? <Badge tone="warn">Pending</Badge> : null}
            {t.needs_review ? <Badge tone="warn">Needs review</Badge> : null}
          </div>
          <div className="mt-0.5 text-xs text-muted">
            {formatDate(t.txn_date)} · {t.account_name} ·{' '}
            {t.category_name ? (t.category_parent ? `${t.category_parent} › ${t.category_name}` : t.category_name) : 'Uncategorized'}
          </div>
          {t.merchant && t.merchant !== t.description_raw ? (
            <div className="mt-0.5 truncate text-xs text-subtle">{t.description_raw}</div>
          ) : null}
          {t.tags.length > 0 ? (
            <div className="mt-1.5 flex flex-wrap gap-1">
              {t.tags.map((tag) => (
                <Badge key={tag} tone="muted">
                  #{tag}
                </Badge>
              ))}
            </div>
          ) : null}
          {t.needs_review && t.review_question ? (
            <p className="mt-1.5 text-xs font-medium text-warn">Question: {t.review_question}</p>
          ) : null}
          {t.note ? <p className="mt-1 text-xs text-muted">Note: {t.note}</p> : null}
        </div>
        <Money value={t.amount} signed showPlus className="shrink-0 text-sm font-semibold" />
      </div>
      <div className="mt-1 flex flex-wrap items-center gap-x-4">
        <label className="-ml-1 flex min-h-10 cursor-pointer items-center gap-2 px-1 text-xs text-ink">
          <input
            type="checkbox"
            checked={cleared}
            onChange={(e) => void toggleCleared(e.target.checked)}
            className="h-5 w-5 accent-[var(--accent)]"
          />
          Cleared
        </label>
        <label
          className="flex min-h-10 items-center gap-2 text-xs text-muted"
          title={t.reconciled ? 'Reconciled by Claude against a bank screenshot' : 'Only Claude can reconcile'}
        >
          <input type="checkbox" checked={t.reconciled} disabled readOnly className="h-5 w-5" aria-label="Reconciled (set only by Claude)" />
          Reconciled
        </label>
        {manual && !t.reconciled ? (
          <button
            type="button"
            onClick={() => openEdit(t)}
            className="-mr-2 ml-auto inline-flex min-h-10 items-center gap-1 rounded-lg px-3 text-sm font-medium text-accent hover:bg-surface-2 focus-visible:outline-2 focus-visible:outline-accent"
          >
            <Icon name="edit" size={16} /> Edit
          </button>
        ) : null}
      </div>
      {toggleError ? (
        <p role="alert" className="mt-1 text-xs text-danger">
          {toggleError}
        </p>
      ) : null}
    </li>
  );
}

function Pagination({
  page,
  from,
  shown,
  total,
  onPage,
}: {
  page: number;
  from: number;
  shown: number;
  total: number | null;
  onPage: (page: number) => void;
}) {
  const hasNext = total !== null ? from + shown < total : shown === PAGE_SIZE;
  return (
    <nav aria-label="Pagination" className="mt-4 flex items-center justify-between gap-3 border-t border-line pt-4">
      <span className="text-xs text-muted tabular-nums">
        {formatCount(from + 1)}–{formatCount(from + shown)}
        {total !== null ? ` of ${formatCount(total)}` : ''}
      </span>
      <div className="flex gap-2">
        <Button onClick={() => onPage(page - 1)} disabled={page <= 1} ariaLabel="Previous page">
          <Icon name="chevronLeft" size={16} /> Prev
        </Button>
        <Button onClick={() => onPage(page + 1)} disabled={!hasNext} ariaLabel="Next page">
          Next <Icon name="chevronRight" size={16} />
        </Button>
      </div>
    </nav>
  );
}
