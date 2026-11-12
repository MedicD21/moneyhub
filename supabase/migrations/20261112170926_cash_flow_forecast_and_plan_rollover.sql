-- =============================================================================
-- 1) paycheck_plan: the active debt plan's per-month extra (rollover + extra) instead of a flat
--    extra_monthly. Plans whose schedule rows carry "minimum" give extra = sum(payment - minimum)
--    for the month; older plans fall back to extra_monthly.
-- =============================================================================
create or replace function public.debt_plan_extra_for_month(p_date date)
 returns numeric
 language sql
 stable
 set search_path to ''
as $function$
  select case
           when p.id is null then null
           when exists (select 1 from jsonb_array_elements(p.schedule) e where e ? 'minimum') then
             coalesce((select round(sum((e->>'payment')::numeric - (e->>'minimum')::numeric), 2)
                         from jsonb_array_elements(p.schedule) e
                        where left(e->>'month', 7) = to_char(p_date, 'YYYY-MM')), 0)
           else p.extra_monthly
         end
  from (select 1) one
  left join public.debt_plans p on p.is_active
  limit 1;
$function$;
comment on function public.debt_plan_extra_for_month(date) is
  'Active plan''s payment above minimums for the month of p_date (rollover + extra). NULL when no plan is active.';

do $mig$
declare
  v_def text := pg_get_functiondef('public.paycheck_plan(date)'::regprocedure);
  v_old text := E'  select dp.extra_monthly into v_extra_month\n  from public.debt_plans dp\n  where dp.is_active\n  limit 1;';
  v_new text := E'  v_extra_month := public.debt_plan_extra_for_month(v_start);';
begin
  if position(v_old in v_def) = 0 then
    raise exception 'paycheck_plan extra-payment clause not found; edit manually';
  end if;
  execute replace(v_def, v_old, v_new);
end $mig$;

-- =============================================================================
-- 2) Cash-flow forecast (first version). Superseded by 20261112171106_forecast_levelized_spending,
--    which drops and recreates pay_period_forecast; kept verbatim so the repo matches the
--    remote migration history.
-- =============================================================================
create or replace function public.pay_period_forecast(p_periods int default 7, p_lookahead int default 6)
 returns table(
   period_index int, period_start date, period_end date, next_pay_date date, is_current boolean,
   expected_net numeric, income_in numeric, obligations numeric,
   starting_cash numeric, cash_as_of date, low_balance_floor numeric,
   safe_to_spend numeric, hold_for_later numeric, carry_out numeric,
   binding_date date, binding_balance numeric, shortfall boolean, income_received boolean)
 language sql
 stable
 set search_path to ''
as $function$
  with cfg as (
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
    select e.k, e.ev_date, e.amount,
           row_number() over (order by e.ev_date,
                                       case when e.kind = 'start' then -1 when e.amount < 0 then 0 else 1 end,
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
           (select min(b.balance) from bal b where b.ev_date >= greatest(pr.pay_date, cfg.today)) as m,
           (select b.ev_date from bal b where b.ev_date >= greatest(pr.pay_date, cfg.today)
             order by b.balance, b.seq limit 1) as binding_date,
           (select b.balance from bal b where b.ev_date < pr.nxt order by b.seq desc limit 1) as bal_end,
           coalesce((select sum(e.amount) from ev e where e.k = pr.k and e.amount > 0 and not e.received), 0) as income_in,
           coalesce((select -sum(e.amount) from ev e where e.k = pr.k and e.amount < 0), 0) as obligations,
           exists (select 1 from ev e where e.k = pr.k and e.kind = 'income' and e.received) as income_received
    from periods pr, cfg
  ),
  calc as (
    select per.*, cfg.floor, cash.bal as start_bal, cash.as_of,
           case when per.k = 1 then per.m - cfg.floor
                else per.m - lag(per.m) over (order by per.k) end as s,
           per.bal_end - (per.m - cfg.floor) as carry
    from per, cfg, cash
  )
  select c.k, c.pay_date, c.nxt - 1, c.nxt, c.is_current,
         c.expected_net, round(c.income_in, 2), round(c.obligations, 2),
         round(c.start_bal, 2), c.as_of, c.floor,
         round(c.s, 2),
         round(c.carry - coalesce(lag(c.carry) over (order by c.k), c.start_bal), 2),
         round(c.carry, 2),
         c.binding_date, round(c.m, 2),
         c.k = 1 and c.m < c.floor,
         c.income_received
  from calc c
  where c.k <= p_periods
  order by c.k;
$function$;

create view public.v_pay_period_forecast with (security_invoker = true) as
  select * from public.pay_period_forecast();

grant execute on function public.debt_plan_extra_for_month(date) to authenticated;
grant execute on function public.pay_period_forecast(int, int) to authenticated;
revoke all on public.v_pay_period_forecast from anon, public;
grant select on public.v_pay_period_forecast to authenticated;
