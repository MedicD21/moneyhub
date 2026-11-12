-- =============================================================================
-- Money Hub — views (all the math). Every view is security_invoker so RLS on
-- the underlying tables applies to whoever queries the view.
--
-- Signed convention inside views: positive = you have it, negative = you owe it.
-- Liability accounts (credit_card, loan) store balances as displayed (positive
-- owed), so they are negated here before any arithmetic.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- v_transactions: transactions joined to account + category (web app table).
-- ---------------------------------------------------------------------------
create view public.v_transactions with (security_invoker = true) as
select
  t.id,
  t.txn_date,
  date_trunc('month', t.txn_date::timestamp)::date as month,
  t.description_raw,
  t.merchant,
  t.amount,
  t.status,
  t.account_id,
  a.name  as account_name,
  a.kind  as account_kind,
  t.category_id,
  c.name  as category_name,
  c.parent_name as category_parent,
  c.kind  as category_kind,
  t.tags,
  t.needs_review,
  t.review_question,
  t.bill_occurrence_id,
  t.debt_id,
  t.note,
  t.import_batch_id,
  t.occurrence,
  t.created_at
from public.transactions t
join public.accounts a on a.id = t.account_id
left join public.categories c on c.id = t.category_id;

-- ---------------------------------------------------------------------------
-- v_account_balances
-- estimated_balance (signed) = last snapshot (signed)
--   + posted transactions dated after the snapshot
--   + pending transactions (any date) when the bank's balance excludes pending,
--     or pending dated after the snapshot when it includes them.
-- ---------------------------------------------------------------------------
create view public.v_account_balances with (security_invoker = true) as
with last_snap as (
  select distinct on (bs.account_id)
         bs.account_id, bs.id as snapshot_id, bs.as_of_date, bs.balance, bs.available
  from public.balance_snapshots bs
  order by bs.account_id, bs.as_of_date desc, bs.created_at desc, bs.id desc
),
base as (
  select a.id, a.name, a.institution, a.kind, a.last4, a.is_active, a.balance_includes_pending,
         a.kind in ('credit_card','loan') as is_liability,
         ls.snapshot_id, ls.as_of_date, ls.balance as snap_display, ls.available,
         case when a.kind in ('credit_card','loan') then -ls.balance else ls.balance end as snap_signed
  from public.accounts a
  left join last_snap ls on ls.account_id = a.id
)
select
  b.id                         as account_id,
  b.name,
  b.institution,
  b.kind,
  b.last4,
  b.is_active,
  b.is_liability,
  b.snapshot_id                as last_snapshot_id,
  b.as_of_date                 as last_snapshot_date,
  b.snap_display               as last_snapshot_balance,
  b.available                  as last_snapshot_available,
  t.since_snapshot             as transactions_since_snapshot,
  t.pending_total,
  b.snap_signed + t.since_snapshot as estimated_balance,
  case when b.is_liability then -(b.snap_signed + t.since_snapshot)
       else b.snap_signed + t.since_snapshot end as estimated_balance_display,
  public.app_today() - b.as_of_date as days_since_screenshot,
  coalesce(not b.is_liability
           and b.snap_signed + t.since_snapshot
               < (select s.low_balance_threshold from public.app_settings s where s.id), false)
                               as is_low_balance
from base b
cross join lateral (
  select
    coalesce(sum(tx.amount) filter (where
        (tx.txn_date > b.as_of_date and (tx.status = 'posted' or b.balance_includes_pending))
     or (tx.status = 'pending' and not b.balance_includes_pending)), 0) as since_snapshot,
    coalesce(sum(tx.amount) filter (where tx.status = 'pending'), 0)  as pending_total
  from public.transactions tx
  where tx.account_id = b.id
) t;

-- ---------------------------------------------------------------------------
-- v_balance_check: for each snapshot after an account's first one,
--   expected = previous snapshot + transactions dated (prev.as_of, this.as_of]
--   difference = actual - expected  (= net amount of transactions missing or
--   misread in the DB; 0 means the data reconciles).
-- Pending rows count only when the account's displayed balance includes pending.
-- ---------------------------------------------------------------------------
create view public.v_balance_check with (security_invoker = true) as
with s as (
  select bs.id, bs.account_id, bs.import_batch_id, bs.as_of_date, bs.created_at,
         a.name as account_name, a.balance_includes_pending,
         case when a.kind in ('credit_card','loan') then -bs.balance else bs.balance end as signed_balance,
         lag(bs.id) over w         as prev_id,
         lag(bs.as_of_date) over w as prev_as_of,
         lag(case when a.kind in ('credit_card','loan') then -bs.balance else bs.balance end) over w as prev_signed,
         row_number() over (partition by bs.account_id
                            order by bs.as_of_date desc, bs.created_at desc, bs.id desc) as recency
  from public.balance_snapshots bs
  join public.accounts a on a.id = bs.account_id
  window w as (partition by bs.account_id order by bs.as_of_date, bs.created_at, bs.id)
)
select
  s.id                 as snapshot_id,
  s.account_id,
  s.account_name,
  s.import_batch_id,
  s.prev_id            as prev_snapshot_id,
  s.prev_as_of         as prev_as_of_date,
  s.prev_signed        as prev_balance,
  s.as_of_date,
  w.txn_sum            as transactions_between,
  w.txn_count,
  w.pending_between,
  s.prev_signed + w.txn_sum                    as expected_balance,
  s.signed_balance                             as actual_balance,
  s.signed_balance - (s.prev_signed + w.txn_sum) as difference,
  s.recency = 1        as is_latest,
  case
    when s.signed_balance - (s.prev_signed + w.txn_sum) = 0 then 'ok'
    when w.pending_between <> 0
         and abs(s.signed_balance - (s.prev_signed + w.txn_sum)) = abs(w.pending_between)
      then 'pending timing: difference equals pending transactions in the window'
    when mod(abs(s.signed_balance - (s.prev_signed + w.txn_sum)) * 100, 9) = 0
      then 'possible transposed/misread digits (difference divisible by 9 cents) or a missing transaction'
    else 'missing or misread transaction'
  end as likely_cause
from s
cross join lateral (
  select coalesce(sum(t.amount) filter (where t.status = 'posted' or s.balance_includes_pending), 0) as txn_sum,
         count(*) filter (where t.status = 'posted' or s.balance_includes_pending)               as txn_count,
         coalesce(sum(t.amount) filter (where t.status = 'pending'), 0)                         as pending_between
  from public.transactions t
  where t.account_id = s.account_id
    and t.txn_date >  s.prev_as_of
    and t.txn_date <= s.as_of_date
) w
where s.prev_id is not null;

-- ---------------------------------------------------------------------------
-- v_month_spending: month x category. Excludes transfer-kind categories.
-- total_out is a positive number (money out); total_in is refunds/income.
-- ---------------------------------------------------------------------------
create view public.v_month_spending with (security_invoker = true) as
select
  date_trunc('month', t.txn_date::timestamp)::date          as month,
  t.category_id,
  coalesce(c.name, 'Uncategorized')                         as category_name,
  c.parent_name                                              as category_parent,
  c.kind                                                     as category_kind,
  coalesce(sum(-t.amount) filter (where t.amount < 0), 0)    as total_out,
  coalesce(sum(t.amount)  filter (where t.amount > 0), 0)    as total_in,
  sum(t.amount)                                              as net,
  count(*)                                                   as txn_count
from public.transactions t
left join public.categories c on c.id = t.category_id
where c.kind is distinct from 'transfer'
group by 1, 2, 3, 4, 5;

-- ---------------------------------------------------------------------------
-- v_cash_flow: per month income, spending, net (transfers excluded).
--   income   = income-kind categories (+ uncategorized money in)
--   spending = expense + debt_payment categories, net of refunds
--              (+ uncategorized money out)
-- ---------------------------------------------------------------------------
create view public.v_cash_flow with (security_invoker = true) as
select month, income, spending, income - spending as net, uncategorized_count
from (
  select
    date_trunc('month', t.txn_date::timestamp)::date as month,
    coalesce(sum(t.amount) filter (where c.kind = 'income' or (c.kind is null and t.amount > 0)), 0) as income,
    coalesce(-sum(t.amount) filter (where c.kind in ('expense','debt_payment')
                                       or (c.kind is null and t.amount < 0)), 0)                  as spending,
    count(*) filter (where t.category_id is null)                                                  as uncategorized_count
  from public.transactions t
  left join public.categories c on c.id = t.category_id
  where c.kind is distinct from 'transfer'
  group by 1
) x;

-- ---------------------------------------------------------------------------
-- v_bill_status / v_upcoming_bills / v_monthly_bills_total
-- ---------------------------------------------------------------------------
create view public.v_bill_status with (security_invoker = true) as
select
  o.id                as occurrence_id,
  o.bill_id,
  b.name              as bill_name,
  o.due_date,
  date_trunc('month', o.due_date::timestamp)::date as due_month,
  o.expected_amount,
  o.paid_amount,
  o.paid_date,
  o.status,
  case when o.status in ('due','partial')
       then greatest(o.expected_amount - coalesce(o.paid_amount, 0), 0) else 0 end as remaining_amount,
  o.due_date - public.app_today() as days_until_due,
  (o.status in ('due','partial') and o.due_date < public.app_today()) as overdue,
  b.autopay,
  b.is_variable,
  b.frequency,
  b.pay_from_account_id,
  pa.name             as pay_from_account_name,
  b.category_id,
  c.name              as category_name,
  o.transaction_id
from public.bill_occurrences o
join public.bills b on b.id = o.bill_id
left join public.accounts pa on pa.id = b.pay_from_account_id
left join public.categories c on c.id = b.category_id;

create view public.v_upcoming_bills with (security_invoker = true) as
select *
from public.v_bill_status
where status in ('due','partial')
  and due_date <= public.app_today() + 30;
comment on view public.v_upcoming_bills is
  'Unpaid (due/partial) bill occurrences due within 30 days, including overdue ones.';

create view public.v_monthly_bills_total with (security_invoker = true) as
select
  coalesce(round(sum(m.monthly), 2), 0)                         as monthly_total,
  coalesce(round(sum(m.monthly) filter (where m.autopay), 2), 0) as autopay_monthly_total,
  coalesce(round(sum(m.monthly) filter (where m.is_variable), 2), 0) as variable_monthly_total,
  count(*)                                                      as active_bill_count
from (
  select b.autopay, b.is_variable,
         case b.frequency
           when 'weekly'    then b.amount * 52 / 12
           when 'biweekly'  then b.amount * 26 / 12
           when 'monthly'   then b.amount
           when 'quarterly' then b.amount / 3
           when 'annual'    then b.amount / 12
         end as monthly
  from public.bills b
  where b.is_active
) m;

-- ---------------------------------------------------------------------------
-- v_debts: latest balance per debt. If the debt is linked to a credit_card /
-- loan account whose screenshot is at least as recent as the last
-- debt_balances row, the account's estimated balance is used instead
-- (balance_source tells you which).
-- ---------------------------------------------------------------------------
create view public.v_debts with (security_invoker = true) as
with latest_db as (
  select distinct on (db.debt_id) db.debt_id, db.as_of_date, db.balance
  from public.debt_balances db
  order by db.debt_id, db.as_of_date desc, db.created_at desc, db.id desc
)
select
  d.id              as debt_id,
  d.name,
  d.kind,
  d.account_id,
  ab.name           as account_name,
  d.apr,
  d.promo_apr,
  d.promo_ends,
  case when d.promo_apr is not null and d.promo_ends >= public.app_today()
       then d.promo_apr else d.apr end as effective_apr,
  d.min_payment,
  d.due_day,
  case when d.due_day is not null then
    (select min(x) from public.bill_due_dates('monthly', d.due_day, null,
                                              public.app_today(), public.app_today() + 40) x)
  end as next_due_date,
  d.credit_limit,
  case when src.use_account then ab.estimated_balance_display else ldb.balance end as balance,
  case when src.use_account then ab.last_snapshot_date      else ldb.as_of_date end as balance_as_of,
  case when src.use_account then 'account_snapshot'
       when ldb.debt_id is not null then 'debt_balances' end as balance_source,
  case when d.credit_limit > 0
        and (case when src.use_account then ab.estimated_balance_display else ldb.balance end) is not null
       then round((case when src.use_account then ab.estimated_balance_display else ldb.balance end)
                  / d.credit_limit * 100, 1) end as utilization_pct,
  d.is_active
from public.debts d
left join latest_db ldb on ldb.debt_id = d.id
left join public.v_account_balances ab on ab.account_id = d.account_id
cross join lateral (
  select coalesce(ab.is_liability and ab.last_snapshot_date is not null
                  and (ldb.as_of_date is null or ab.last_snapshot_date >= ldb.as_of_date), false) as use_account
) src;

-- ---------------------------------------------------------------------------
-- v_review_queue
-- ---------------------------------------------------------------------------
create view public.v_review_queue with (security_invoker = true) as
select *
from public.v_transactions
where needs_review;

-- ---------------------------------------------------------------------------
-- Debt history + active plan (web app Debts page)
-- ---------------------------------------------------------------------------
create view public.v_debt_balance_history with (security_invoker = true) as
select d.id as debt_id, d.name as debt_name, db.as_of_date, db.balance, 'debt_balances'::text as source
from public.debt_balances db
join public.debts d on d.id = db.debt_id
union all
select d.id, d.name, bs.as_of_date, bs.balance, 'account_snapshot'::text
from public.balance_snapshots bs
join public.accounts a on a.id = bs.account_id and a.kind in ('credit_card','loan')
join public.debts d on d.account_id = bs.account_id;

create view public.v_active_debt_plan with (security_invoker = true) as
select p.id as plan_id, p.name, p.strategy, p.extra_monthly, p.assumptions, p.summary,
       p.balances_as_of, p.created_at
from public.debt_plans p
where p.is_active;

create view public.v_debt_plan_schedule with (security_invoker = true) as
select
  p.id                                                      as plan_id,
  to_date(left(e->>'month', 7) || '-01', 'YYYY-MM-DD')      as month,
  (e->>'debt_id')::uuid                                     as debt_id,
  d.name                                                    as debt_name,
  (e->>'start')::numeric(12,2)                              as start_balance,
  (e->>'interest')::numeric(12,2)                           as interest,
  (e->>'payment')::numeric(12,2)                            as payment,
  (e->>'end')::numeric(12,2)                                as end_balance
from public.debt_plans p
cross join lateral jsonb_array_elements(p.schedule) e
left join public.debts d on d.id = (e->>'debt_id')::uuid
where p.is_active;

create view public.v_debt_plan_projection with (security_invoker = true) as
select month,
       sum(end_balance) as total_end_balance,
       sum(interest)    as total_interest,
       sum(payment)     as total_payment
from public.v_debt_plan_schedule
group by month;

-- ---------------------------------------------------------------------------
-- v_bill_match_candidates: unmatched outflows whose description contains a
-- bill's match_pattern, near an unpaid occurrence (20 days before to 10 days
-- after the due date). rank = 1 is the closest occurrence for that transaction.
-- Claude confirms, then calls mark_bill_paid().
-- ---------------------------------------------------------------------------
create view public.v_bill_match_candidates with (security_invoker = true) as
select *
from (
  select
    t.id                 as transaction_id,
    t.import_batch_id,
    t.txn_date,
    t.description_raw,
    t.amount,
    o.id                 as occurrence_id,
    b.id                 as bill_id,
    b.name               as bill_name,
    o.due_date,
    o.expected_amount,
    o.status             as occurrence_status,
    abs(t.amount) >= o.expected_amount - coalesce(o.paid_amount, 0) or b.is_variable as would_be_paid_in_full,
    row_number() over (partition by t.id order by abs(t.txn_date - o.due_date), o.due_date) as rank
  from public.transactions t
  join public.bills b
    on b.is_active
   and b.match_pattern is not null
   and position(lower(b.match_pattern) in lower(t.description_raw)) > 0
   and (b.pay_from_account_id is null or b.pay_from_account_id = t.account_id)
  join public.bill_occurrences o
    on o.bill_id = b.id
   and o.status in ('due','partial')
   and t.txn_date between o.due_date - 20 and o.due_date + 10
  where t.amount < 0
    and t.bill_occurrence_id is null
) x;
