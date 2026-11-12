-- Rewrite pay_period_forecast (return columns change, so drop + recreate with its view).
-- safe_to_spend is now LEVELIZED: the largest steady amount per period such that cumulative spending
-- through any period j never exceeds A_j = (lowest projected balance from period j onward) - floor.
--   L_k = min over j >= k of (A_j - C_(k-1)) / (j - k + 1),  C = cumulative L.
-- max_safe_to_spend = A_k - C_(k-1): the ceiling for this period if later periods spend nothing extra.
-- Includes the two earlier fixes: deposits before same-day bills; the starting-cash anchor is not a low point.
drop view if exists public.v_pay_period_forecast;
drop function if exists public.pay_period_forecast(int, int);

create function public.pay_period_forecast(p_periods int default 7, p_lookahead int default 6)
 returns table(
   period_index int, period_start date, period_end date, next_pay_date date, is_current boolean,
   expected_net numeric, income_in numeric, obligations numeric,
   starting_cash numeric, cash_as_of date, low_balance_floor numeric,
   safe_to_spend numeric, max_safe_to_spend numeric, hold_for_later numeric, carry_out numeric,
   binding_date date, binding_balance numeric, shortfall boolean, income_received boolean)
 language sql
 stable
 set search_path to ''
as $function$
  with recursive cfg as (
    select public.app_today() as today,
           coalesce((select s.low_balance_threshold from public.app_settings s where s.id), 0) as floor
  ),
  cash as (
    select coalesce(sum(ab.estimated_balance), 0) as bal, min(ab.last_snapshot_date) as as_of
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
comment on function public.pay_period_forecast(int, int) is
  'Balance-anchored cash-flow forecast per pay period. safe_to_spend = levelized steady amount that keeps the projected balance >= app_settings.low_balance_threshold through the look-ahead (covers short paychecks and bill clusters); max_safe_to_spend = ceiling for this period alone; hold_for_later = what this period leaves behind for later low points (negative = draws on earlier holds).';

create view public.v_pay_period_forecast with (security_invoker = true) as
  select * from public.pay_period_forecast();

revoke execute on function public.pay_period_forecast(int, int) from public, anon;
grant execute on function public.pay_period_forecast(int, int) to authenticated;
revoke all on public.v_pay_period_forecast from anon, public;
grant select on public.v_pay_period_forecast to authenticated;
