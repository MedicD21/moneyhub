-- =============================================================================
-- Money Hub — paycheck_plan(), v_pay_periods, v_dashboard
-- =============================================================================

-- paycheck_plan(p_pay_date)
--   Period = [latest payday <= p_pay_date (default today), next payday).
--   Pay periods are defined by the union of all active income sources' paydays.
--
--   expected_net     = sum of paychecks landing on period_start
--   bills_total      = unpaid remainder of bill occurrences due in the period
--                      + (current period only) overdue unpaid occurrences
--                      + projected occurrences not yet generated (>= this month)
--   minimums_total   = debt minimums whose due_day falls in the period, less
--                      payments already linked to that debt (debt_id) in the
--                      month before the due date, capped at the debt's balance
--   set_asides_total = sum of active set_asides.per_paycheck
--   extra_debt       = active debt_plans.extra_monthly x 12 / paydays per year
--   safe_to_spend    = expected_net - bills - minimums - set_asides - extra_debt
--   spent_so_far     = discretionary spending since period_start (expense-kind
--                      or uncategorized outflows not linked to a bill or debt)
--   remaining_safe_to_spend = safe_to_spend - spent_so_far
create or replace function public.paycheck_plan(p_pay_date date default null)
returns table (
  period_start             date,
  period_end               date,
  next_pay_date            date,
  is_current               boolean,
  expected_net             numeric,
  bills_total              numeric,
  minimums_total           numeric,
  set_asides_total         numeric,
  extra_debt               numeric,
  safe_to_spend            numeric,
  shortfall                boolean,
  spent_so_far             numeric,
  remaining_safe_to_spend  numeric,
  items                    jsonb
)
language plpgsql
stable
security invoker
rows 1
set search_path = ''
set jit = off  -- tiny row counts; JIT compile time (~750 ms) dwarfs execution
as $$
#variable_conflict use_column
declare
  v_today        date := public.app_today();
  v_ref          date := coalesce(p_pay_date, public.app_today());
  v_gen_from     date := date_trunc('month', public.app_today()::timestamp)::date;
  v_start        date;
  v_next         date;
  v_current      boolean;
  v_net          numeric := 0;
  v_bills        numeric := 0;
  v_mins         numeric := 0;
  v_sets         numeric := 0;
  v_extra        numeric := 0;
  v_extra_month  numeric;
  v_paydays_year int;
  v_spent        numeric := 0;
  v_safe         numeric;
  i_income       jsonb := '[]';
  i_bills        jsonb := '[]';
  i_mins         jsonb := '[]';
  i_sets         jsonb := '[]';
  i_extra        jsonb := '[]';
begin
  select max(pd.pay_date) into v_start
  from public.pay_dates(v_ref - 70, v_ref) pd;

  if v_start is null then
    return;  -- no active income source covers this date
  end if;

  select min(pd.pay_date) into v_next
  from public.pay_dates(v_start + 1, v_start + 70) pd;
  v_next := coalesce(v_next, (v_start + interval '1 month')::date);

  v_current := v_today >= v_start and v_today < v_next;

  -- Income
  select coalesce(sum(pd.expected_net), 0),
         coalesce(jsonb_agg(jsonb_build_object(
           'type', 'income', 'id', pd.income_source_id, 'name', s.name,
           'date', pd.pay_date, 'amount', pd.expected_net) order by s.name), '[]')
    into v_net, i_income
  from public.pay_dates(v_start, v_start) pd
  join public.income_sources s on s.id = pd.income_source_id;

  -- Bills
  with occ as (
    select o.id as occurrence_id, b.id as bill_id, b.name, o.due_date, o.status,
           greatest(o.expected_amount - coalesce(o.paid_amount, 0), 0) as amt,
           o.due_date < v_start as overdue,
           false as projected
    from public.bill_occurrences o
    join public.bills b on b.id = o.bill_id
    where o.status in ('due','partial')
      and ((o.due_date >= v_start and o.due_date < v_next)
           or (v_current and o.due_date < v_start))
  ),
  proj as (
    select null::uuid as occurrence_id, b.id as bill_id, b.name, d as due_date, 'projected'::text as status,
           b.amount as amt, false as overdue, true as projected
    from public.bills b
    cross join lateral public.bill_due_dates(b.frequency, b.due_day, b.anchor_date,
                                             greatest(v_start, v_gen_from), v_next - 1) d
    where b.is_active
      and not exists (select 1 from public.bill_occurrences o where o.bill_id = b.id and o.due_date = d)
  ),
  all_bills as (
    select * from occ union all select * from proj
  )
  select coalesce(sum(ab.amt), 0),
         coalesce(jsonb_agg(jsonb_build_object(
           'type', 'bill', 'id', ab.bill_id, 'occurrence_id', ab.occurrence_id, 'name', ab.name,
           'date', ab.due_date, 'amount', ab.amt, 'status', ab.status,
           'overdue', ab.overdue, 'projected', ab.projected) order by ab.due_date, ab.name), '[]')
    into v_bills, i_bills
  from all_bills ab
  where ab.amt > 0;

  -- Debt minimums
  with dm as (
    select d.id, d.name, dd as due_date,
           greatest(least(d.min_payment, coalesce(vd.balance, d.min_payment)), 0) as min_due,
           coalesce((select -sum(t.amount)
                       from public.transactions t
                      where t.debt_id = d.id
                        and t.amount < 0
                        and t.txn_date >  (dd - interval '1 month')::date
                        and t.txn_date <= dd), 0) as paid
    from public.debts d
    left join public.v_debts vd on vd.debt_id = d.id
    cross join lateral public.bill_due_dates('monthly', d.due_day, null, v_start, v_next - 1) dd
    where d.is_active and d.due_day is not null
  )
  select coalesce(sum(greatest(dm.min_due - dm.paid, 0)), 0),
         coalesce(jsonb_agg(jsonb_build_object(
           'type', 'debt_minimum', 'id', dm.id, 'name', dm.name, 'date', dm.due_date,
           'amount', greatest(dm.min_due - dm.paid, 0), 'already_paid', dm.paid)
           order by dm.due_date, dm.name) filter (where dm.min_due - dm.paid > 0), '[]')
    into v_mins, i_mins
  from dm;

  -- Set-asides
  select coalesce(sum(sa.per_paycheck), 0),
         coalesce(jsonb_agg(jsonb_build_object(
           'type', 'set_aside', 'id', sa.id, 'name', sa.name, 'amount', sa.per_paycheck)
           order by sa.name) filter (where sa.per_paycheck > 0), '[]')
    into v_sets, i_sets
  from public.set_asides sa
  where sa.is_active;

  -- Extra debt payment from the active plan
  select dp.extra_monthly into v_extra_month
  from public.debt_plans dp
  where dp.is_active
  limit 1;

  if coalesce(v_extra_month, 0) > 0 then
    select count(distinct pd.pay_date) into v_paydays_year
    from public.pay_dates(v_start, v_start + 363) pd;  -- 364-day window: 26 biweekly, 52 weekly, 24 semimonthly, 12 monthly
    if v_paydays_year > 0 then
      v_extra := round(v_extra_month * 12 / v_paydays_year, 2);
      i_extra := jsonb_build_array(jsonb_build_object(
        'type', 'extra_debt', 'name', 'Extra debt payment (active plan)', 'amount', v_extra,
        'extra_monthly', v_extra_month, 'paydays_per_year', v_paydays_year));
    end if;
  end if;

  -- Discretionary spending so far in this period
  if v_start <= v_today then
    select coalesce(-sum(t.amount), 0) into v_spent
    from public.transactions t
    left join public.categories c on c.id = t.category_id
    where t.txn_date >= v_start
      and t.txn_date <  v_next
      and t.txn_date <= v_today
      and t.bill_occurrence_id is null
      and t.debt_id is null
      and (c.kind = 'expense' or (c.kind is null and t.amount < 0));
  end if;

  v_safe := v_net - v_bills - v_mins - v_sets - v_extra;

  period_start            := v_start;
  period_end              := v_next - 1;
  next_pay_date           := v_next;
  is_current              := v_current;
  expected_net            := v_net;
  bills_total             := v_bills;
  minimums_total          := v_mins;
  set_asides_total        := v_sets;
  extra_debt              := v_extra;
  safe_to_spend           := v_safe;
  shortfall               := v_safe < 0;
  spent_so_far            := v_spent;
  remaining_safe_to_spend := v_safe - v_spent;
  items                   := i_income || i_bills || i_mins || i_sets || i_extra;
  return next;
end;
$$;
comment on function public.paycheck_plan(date) is
  'Budget for the pay period containing p_pay_date (default today). See migration header for formulas.';

-- ---------------------------------------------------------------------------
-- v_pay_periods: current period (offset 0), 2 before, 6 after.
-- ---------------------------------------------------------------------------
create view public.v_pay_periods with (security_invoker = true) as
with dates as (
  select distinct pd.pay_date
  from public.pay_dates(public.app_today() - 200, public.app_today() + 400) pd
),
pick as (
  (select d.pay_date from dates d where d.pay_date <= public.app_today() order by d.pay_date desc limit 3)
  union all
  (select d.pay_date from dates d where d.pay_date >  public.app_today() order by d.pay_date limit 6)
)
select
  (row_number() over (order by p.pay_date)
     - (select count(*) from pick p2 where p2.pay_date <= public.app_today()))::int as period_offset,
  pp.*
from pick p
cross join lateral public.paycheck_plan(p.pay_date) pp;

-- ---------------------------------------------------------------------------
-- v_dashboard: one row.
-- ---------------------------------------------------------------------------
create view public.v_dashboard with (security_invoker = true) as
select
  public.app_today() as today,
  cash.total_cash,
  debt.total_debt,
  cash.total_cash - debt.total_debt as net,
  due7.bills_due_7d_count,
  due7.bills_due_7d_total,
  od.overdue_bills_count,
  od.overdue_bills_total,
  np.next_payday,
  np.next_payday_amount,
  pp.period_start,
  pp.period_end,
  pp.expected_net        as period_expected_net,
  pp.safe_to_spend,
  pp.spent_so_far,
  pp.remaining_safe_to_spend,
  pp.shortfall,
  rq.review_queue_count,
  age.oldest_data_days,
  age.accounts_without_snapshot,
  bc.balance_check_issues,
  low.low_balance_accounts,
  st.stale_after_days,
  st.low_balance_threshold
from (select 1) one
cross join lateral (
  select coalesce(sum(ab.estimated_balance), 0) as total_cash
  from public.v_account_balances ab
  where ab.is_active and ab.kind in ('checking','savings','cash')
) cash
cross join lateral (
  select
    (select coalesce(sum(vd.balance), 0) from public.v_debts vd where vd.is_active)
    + (select coalesce(sum(-ab.estimated_balance), 0)
         from public.v_account_balances ab
        where ab.is_active and ab.is_liability
          and not exists (select 1 from public.debts d where d.account_id = ab.account_id and d.is_active))
    as total_debt
) debt
cross join lateral (
  select count(*) as bills_due_7d_count, coalesce(sum(bs.remaining_amount), 0) as bills_due_7d_total
  from public.v_bill_status bs
  where bs.status in ('due','partial')
    and bs.due_date between public.app_today() and public.app_today() + 7
) due7
cross join lateral (
  select count(*) as overdue_bills_count, coalesce(sum(bs.remaining_amount), 0) as overdue_bills_total
  from public.v_bill_status bs
  where bs.overdue
) od
left join lateral (
  select pd.pay_date as next_payday, sum(pd.expected_net) as next_payday_amount
  from public.pay_dates(public.app_today(), public.app_today() + 70) pd
  group by pd.pay_date
  order by pd.pay_date
  limit 1
) np on true
left join lateral public.paycheck_plan() pp on true
cross join lateral (
  select count(*) as review_queue_count from public.transactions t where t.needs_review
) rq
cross join lateral (
  select max(ab.days_since_screenshot) as oldest_data_days,
         count(*) filter (where ab.last_snapshot_date is null) as accounts_without_snapshot
  from public.v_account_balances ab
  where ab.is_active
) age
cross join lateral (
  select count(*) as balance_check_issues
  from public.v_balance_check bc
  where bc.is_latest and bc.difference <> 0
) bc
cross join lateral (
  select count(*) as low_balance_accounts
  from public.v_account_balances ab
  where ab.is_active and ab.is_low_balance
) low
left join lateral (
  select s.stale_after_days, s.low_balance_threshold from public.app_settings s where s.id
) st on true;
