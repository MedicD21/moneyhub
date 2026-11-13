-- Forecast: explain WHY a period is short. Adds to pay_period_forecast / v_pay_period_forecast:
--   cash_before_spending  cash left when this period ends, before spending this period's
--                         safe_to_spend (after earlier periods' planned spending)
--   next_income           paycheck(s) still to arrive in the following period
--   next_obligations      bills, minimums and set-asides due in the following period
--   next_draw             next_obligations - next_income: what the following period takes from
--                         this period's leftover cash (negative = it adds cash)
--   next_period_end       last day of the following period
-- The web app only displays these (the database does all the math).
-- Return type changes, so the view and function are dropped and recreated.
drop view public.v_pay_period_forecast;
drop function public.pay_period_forecast(integer, integer);

create function public.pay_period_forecast(p_periods integer default 7, p_lookahead integer default 6)
 returns table(period_index integer, period_start date, period_end date, next_pay_date date, is_current boolean,
               expected_net numeric, income_in numeric, obligations numeric, starting_cash numeric, cash_as_of date,
               low_balance_floor numeric, safe_to_spend numeric, max_safe_to_spend numeric, hold_for_later numeric,
               carry_out numeric, binding_date date, binding_balance numeric, shortfall boolean, income_received boolean,
               cash_before_spending numeric, next_income numeric, next_obligations numeric, next_draw numeric,
               next_period_end date)
 language sql
 stable
 set search_path to ''
as $function$
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
  ),
  fin as (
    -- window functions run before the period_index filter below so the last returned period
    -- still sees the period that follows it
    select c.*,
           lag(c.carry) over (order by c.k) as prev_carry,
           lead(c.income_in) over (order by c.k) as nx_income,
           lead(c.obligations) over (order by c.k) as nx_obligations,
           lead(c.nxt) over (order by c.k) as nx_nxt
    from calc c
  )
  select c.k, c.pay_date, c.nxt - 1, c.nxt, c.is_current,
         c.expected_net, round(c.income_in, 2), round(c.obligations, 2),
         round(c.start_bal, 2), c.as_of, c.floor,
         round(c.l, 2),
         round(c.a - c.c_prev, 2),
         round(c.carry - coalesce(c.prev_carry, c.start_bal), 2),
         round(c.carry, 2),
         c.binding_date, round(c.m, 2),
         c.k = 1 and c.a < 0,
         c.income_received,
         round(c.carry + c.l, 2),
         round(c.nx_income, 2),
         round(c.nx_obligations, 2),
         round(c.nx_obligations - c.nx_income, 2),
         c.nx_nxt - 1
  from fin c
  where c.k <= p_periods
  order by c.k;
$function$;

revoke all on function public.pay_period_forecast(integer, integer) from public, anon;
grant execute on function public.pay_period_forecast(integer, integer) to authenticated, service_role;

create view public.v_pay_period_forecast with (security_invoker = true) as
select period_index, period_start, period_end, next_pay_date, is_current, expected_net, income_in, obligations,
       starting_cash, cash_as_of, low_balance_floor, safe_to_spend, max_safe_to_spend, hold_for_later, carry_out,
       binding_date, binding_balance, shortfall, income_received,
       cash_before_spending, next_income, next_obligations, next_draw, next_period_end
from public.pay_period_forecast();

revoke all on public.v_pay_period_forecast from anon, public;
grant select on public.v_pay_period_forecast to authenticated;
