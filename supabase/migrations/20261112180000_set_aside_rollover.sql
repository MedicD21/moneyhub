-- Set-aside rollover ("envelopes").
-- A set-aside now has a running balance: each payday adds per_paycheck (until an optional cap), and
-- spending tagged to it (transactions.set_aside_id) or in its linked category draws it down.
-- The balance is derived from paydays + transactions, never stored, so history stays consistent.
--   * paycheck_plan: the set-aside line is the capped contribution for that payday; spending that draws
--     from a set-aside no longer counts as discretionary spending (it was pre-funded).
--   * pay_period_forecast: starting cash excludes money already reserved in envelopes.
-- Balances may go negative (overspent); the shortfall is repaid by later contributions.

alter table public.set_asides
  add column cap             numeric(12,2) check (cap is null or cap >= 0),
  add column start_date      date not null default public.app_today(),
  add column opening_balance numeric(12,2) not null default 0,
  add column category_id     uuid references public.categories(id) on delete set null;
comment on column public.set_asides.cap is 'Max balance; contributions shrink or stop at the cap. null = unlimited rollover.';
comment on column public.set_asides.start_date is 'Contributions start with the pay period containing this date.';
comment on column public.set_asides.category_id is 'Optional: untagged transactions in this category draw from this set-aside.';

alter table public.transactions
  add column set_aside_id uuid references public.set_asides(id) on delete set null;
comment on column public.transactions.set_aside_id is 'Spending drawn from this set-aside (overrides category matching).';
create index transactions_set_aside_idx on public.transactions (set_aside_id) where set_aside_id is not null;

-- Net spend drawn from a set-aside in [p_from, p_to). Refunds (positive amounts) reduce it.
create function public.set_aside_draws(p_id uuid, p_from date, p_to date)
 returns numeric
 language sql
 stable
 set search_path to ''
as $function$
  select coalesce(-sum(t.amount), 0)
  from public.set_asides sa
  join public.transactions t
    on t.set_aside_id = sa.id
    or (t.set_aside_id is null and sa.category_id is not null and t.category_id = sa.category_id)
  where sa.id = p_id
    and t.txn_date >= p_from
    and t.txn_date <  p_to;
$function$;

-- One row per payday from the period containing start_date through p_through.
-- Future draws are unknown, so periods after today assume no spending from the envelope.
create function public.set_aside_ledger(p_id uuid, p_through date)
 returns table(pay_date date, balance_before numeric, contribution numeric, balance_after numeric, drawn numeric)
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  sa      public.set_asides%rowtype;
  v_first date;
  v_prev  date;
  v_bal   numeric;
  r       record;
begin
  select * into sa from public.set_asides where id = p_id;
  if not found then return; end if;
  select coalesce(max(pd.pay_date), sa.start_date) into v_first
    from public.pay_dates(sa.start_date - 70, sa.start_date) pd
   where pd.pay_date <= sa.start_date;
  v_prev := sa.start_date;
  v_bal  := sa.opening_balance;
  for r in
    select distinct pd.pay_date as d
      from public.pay_dates(v_first, p_through) pd
     where pd.pay_date between v_first and p_through
     order by 1
  loop
    drawn          := public.set_aside_draws(p_id, v_prev, r.d);
    balance_before := v_bal - drawn;
    contribution   := case when sa.cap is null then sa.per_paycheck
                           else least(sa.per_paycheck, greatest(sa.cap - balance_before, 0)) end;
    balance_after  := balance_before + contribution;
    pay_date       := r.d;
    v_bal  := balance_after;
    v_prev := greatest(r.d, v_prev);
    return next;
  end loop;
end;
$function$;
comment on function public.set_aside_ledger(uuid, date) is
  'Rollover ledger for one set-aside: balance_before (after draws since the last payday), capped contribution, balance_after.';

-- Balance today, and the contribution added on the current payday.
create function public.set_aside_position(p_id uuid)
 returns table(balance numeric, current_contribution numeric)
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  l  record;
  sa public.set_asides%rowtype;
begin
  select * into sa from public.set_asides where id = p_id;
  if not found then return; end if;
  select x.* into l from public.set_aside_ledger(p_id, public.app_today()) x order by x.pay_date desc limit 1;
  if found then
    balance := l.balance_after - public.set_aside_draws(p_id, l.pay_date, public.app_today() + 1);
    current_contribution := l.contribution;
  else
    balance := sa.opening_balance - public.set_aside_draws(p_id, sa.start_date, public.app_today() + 1);
    current_contribution := 0;
  end if;
  return next;
end;
$function$;

create view public.v_set_asides with (security_invoker = true) as
select sa.id, sa.name, sa.per_paycheck, sa.cap, sa.is_active, sa.start_date,
       sa.category_id, c.name as category_name,
       pos.balance, pos.current_contribution,
       case when sa.cap is null then null else greatest(sa.cap - pos.balance, 0) end as room_left,
       coalesce(pos.balance >= sa.cap, false) as at_cap
from public.set_asides sa
left join public.categories c on c.id = sa.category_id
cross join lateral public.set_aside_position(sa.id) pos;
comment on view public.v_set_asides is 'Set-asides with their current rollover balance, cap and room left.';

CREATE OR REPLACE FUNCTION public.paycheck_plan(p_pay_date date DEFAULT NULL::date)
 RETURNS TABLE(period_start date, period_end date, next_pay_date date, is_current boolean, expected_net numeric, bills_total numeric, minimums_total numeric, set_asides_total numeric, extra_debt numeric, safe_to_spend numeric, shortfall boolean, spent_so_far numeric, remaining_safe_to_spend numeric, overspent boolean, items jsonb)
 LANGUAGE plpgsql
 STABLE ROWS 1
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
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
      and b.is_active
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
      and (b.end_date is null or d <= b.end_date)
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
                        and t.txn_date >  public.clamp_day(
                                              extract(year  from dd - interval '1 month')::int,
                                              extract(month from dd - interval '1 month')::int,
                                              d.due_day)
                        and t.txn_date <= dd), 0) as paid
    from public.debts d
    left join public.v_debts vd on vd.debt_id = d.id
    cross join lateral public.bill_due_dates('monthly', d.due_day, null, v_start, v_next - 1) dd
    where d.is_active and d.due_day is not null
      and not exists (select 1 from public.bills b where b.debt_id = d.id and b.is_active)
  )
  select coalesce(sum(greatest(dm.min_due - dm.paid, 0)), 0),
         coalesce(jsonb_agg(jsonb_build_object(
           'type', 'debt_minimum', 'id', dm.id, 'name', dm.name, 'date', dm.due_date,
           'amount', greatest(dm.min_due - dm.paid, 0), 'already_paid', dm.paid)
           order by dm.due_date, dm.name) filter (where dm.min_due - dm.paid > 0), '[]')
    into v_mins, i_mins
  from dm;

  -- Set-asides: per-paycheck contribution from the rollover ledger (reduced when the cap is reached)
  select coalesce(sum(l.contribution), 0),
         coalesce(jsonb_agg(jsonb_build_object(
           'type', 'set_aside', 'id', sa.id, 'name', sa.name, 'amount', l.contribution,
           'per_paycheck', sa.per_paycheck, 'cap', sa.cap, 'balance_after', l.balance_after,
           'capped', l.contribution < sa.per_paycheck)
           order by sa.name) filter (where sa.per_paycheck > 0), '[]')
    into v_sets, i_sets
  from public.set_asides sa
  cross join lateral public.set_aside_ledger(sa.id, v_start) l
  where sa.is_active and l.pay_date = v_start;

  -- Extra debt payment from the active plan
  v_extra_month := public.debt_plan_extra_for_month(v_start);

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
      -- spending drawn from a set-aside was pre-funded by it, so it is not discretionary
      and t.set_aside_id is null
      and (t.category_id is null or not exists (
             select 1 from public.set_asides sa where sa.is_active and sa.category_id = t.category_id))
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
  overspent               := v_safe - v_spent < 0;
  items                   := i_income || i_bills || i_mins || i_sets || i_extra;
  return next;
end;
$function$;

CREATE OR REPLACE FUNCTION public.pay_period_forecast(p_periods integer DEFAULT 7, p_lookahead integer DEFAULT 6)
 RETURNS TABLE(period_index integer, period_start date, period_end date, next_pay_date date, is_current boolean, expected_net numeric, income_in numeric, obligations numeric, starting_cash numeric, cash_as_of date, low_balance_floor numeric, safe_to_spend numeric, max_safe_to_spend numeric, hold_for_later numeric, carry_out numeric, binding_date date, binding_balance numeric, shortfall boolean, income_received boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with recursive cfg as (
    select public.app_today() as today,
           coalesce((select s.low_balance_threshold from public.app_settings s where s.id), 0) as floor
  ),
  cash as (
    -- cash already reserved in set-aside envelopes is not spendable (this period's contribution is
    -- excluded: it is modelled as an outflow at payday)
    select coalesce(sum(ab.estimated_balance), 0)
             - coalesce((select sum(greatest(pos.balance - pos.current_contribution, 0))
                           from public.set_asides sa
                           cross join lateral public.set_aside_position(sa.id) pos
                          where sa.is_active), 0) as bal,
           min(ab.last_snapshot_date) as as_of
    from public.v_account_balances ab
    where ab.is_active and ab.kind in ('checking', 'savings', 'cash')
  ),
  cur as (
    select max(pd.pay_date) as d from cfg, public.pay_dates(cfg.today - 70, cfg.today) pd
  ),
  starts as (
    select x.pay_date, (row_number() over (order by x.pay_date))::int as k,
           lead(x.pay_date) over (order by x.pay_date) as nxt
    from (select distinct pd.pay_date
            from cur, public.pay_dates(cur.d, cur.d + 14 * (p_periods + p_lookahead + 2)) pd) x
  ),
  periods as (
    select s.k, s.pay_date, s.nxt, p.is_current, p.expected_net, p.items
    from starts s
    cross join lateral public.paycheck_plan(s.pay_date) p
    where s.nxt is not null and s.k <= p_periods + p_lookahead
  ),
  ev as (
    select pr.k,
           greatest(case when it->>'type' in ('income', 'bill', 'debt_minimum')
                         then (it->>'date')::date else pr.pay_date end, cfg.today) as ev_date,
           case when it->>'type' = 'income' then (it->>'amount')::numeric
                else -(it->>'amount')::numeric end as amount,
           it->>'type' as kind,
           it->>'name' as name,
           (it->>'type' = 'income' and exists (
              select 1
              from public.income_sources src
              join public.transactions t on t.account_id = src.deposit_account_id
              where src.id = (it->>'id')::uuid
                and t.amount >= 0.5 * (it->>'amount')::numeric
                and t.txn_date between (it->>'date')::date - 3 and (it->>'date')::date + 3)) as received
    from periods pr
    cross join cfg
    cross join lateral jsonb_array_elements(pr.items) it
  ),
  path as (
    -- same day: starting anchor, then deposits, then bills
    select e.k, e.ev_date, e.amount,
           row_number() over (order by e.ev_date,
                                       case when e.kind = 'start' then -1 when e.amount >= 0 then 0 else 1 end,
                                       e.k, e.name) as seq
    from (select ev.k, ev.ev_date, ev.amount, ev.kind, ev.name from ev where not ev.received
          union all
          select 0, cfg.today, 0, 'start', '' from cfg) e
  ),
  bal as (
    select p.ev_date, p.seq, cash.bal + sum(p.amount) over (order by p.seq) as balance
    from path p, cash
  ),
  per as (
    select pr.k, pr.pay_date, pr.nxt, pr.is_current, pr.expected_net,
           (select min(b.balance) from bal b
             where b.seq > 1 and b.ev_date >= greatest(pr.pay_date, cfg.today)) as m,
           (select b.ev_date from bal b
             where b.seq > 1 and b.ev_date >= greatest(pr.pay_date, cfg.today)
             order by b.balance, b.seq limit 1) as binding_date,
           (select b.balance from bal b where b.ev_date < pr.nxt order by b.seq desc limit 1) as bal_end,
           coalesce((select sum(e.amount) from ev e where e.k = pr.k and e.amount > 0 and not e.received), 0) as income_in,
           coalesce((select -sum(e.amount) from ev e where e.k = pr.k and e.amount < 0), 0) as obligations,
           exists (select 1 from ev e where e.k = pr.k and e.kind = 'income' and e.received) as income_received
    from periods pr, cfg
  ),
  a as (
    -- A_k: cumulative spending allowed through period k. With no events left (end of horizon)
    -- carry the previous bound forward rather than inventing room.
    select per.k, coalesce(per.m, per.bal_end) - cfg.floor as a from per, cfg
  ),
  lvl (k, c_prev, l) as (
    select 1, 0::numeric,
           (select min((a.a - 0) / (a.k - 1 + 1)) from a where a.k >= 1)
    union all
    select r.k + 1, r.c_prev + r.l,
           (select min((a.a - (r.c_prev + r.l)) / (a.k - (r.k + 1) + 1)) from a where a.k >= r.k + 1)
    from lvl r
    where r.k < (select max(k) from a)
  ),
  calc as (
    select per.*, cfg.floor, cash.bal as start_bal, cash.as_of, a.a,
           lvl.l, lvl.c_prev,
           per.bal_end - (lvl.c_prev + lvl.l) as carry
    from per
    join a on a.k = per.k
    join lvl on lvl.k = per.k
    cross join cfg cross join cash
  )
  select c.k, c.pay_date, c.nxt - 1, c.nxt, c.is_current,
         c.expected_net, round(c.income_in, 2), round(c.obligations, 2),
         round(c.start_bal, 2), c.as_of, c.floor,
         round(c.l, 2),
         round(c.a - c.c_prev, 2),
         round(c.carry - coalesce(lag(c.carry) over (order by c.k), c.start_bal), 2),
         round(c.carry, 2),
         c.binding_date, round(c.m, 2),
         c.k = 1 and c.a < 0,
         c.income_received
  from calc c
  where c.k <= p_periods
  order by c.k;
$function$;


revoke execute on function public.set_aside_draws(uuid, date, date), public.set_aside_ledger(uuid, date),
  public.set_aside_position(uuid) from public, anon;
grant execute on function public.set_aside_draws(uuid, date, date), public.set_aside_ledger(uuid, date),
  public.set_aside_position(uuid) to authenticated;
revoke all on public.v_set_asides from anon, public;
grant select on public.v_set_asides to authenticated;
