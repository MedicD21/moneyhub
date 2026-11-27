-- Day-by-day projected balance for the full-screen bills calendar.
--
-- daily_balance_forecast() walks the SAME events as pay_period_forecast (same cash base, same
-- paycheck_plan items, same "already received income is skipped", same clamp of past-due items to
-- today) and rolls them up to one row per day from today to the end of the last forecast period.
-- projected_balance is the end-of-day SPENDABLE balance: cash already reserved in set-asides and
-- envelopes is excluded, exactly as in pay_period_forecast, so on a forecast binding_date it equals
-- v_pay_period_forecast.binding_balance. It models scheduled items only (no groceries, dining or
-- other discretionary spending).
--
-- Read-only (STABLE, invoker rights, same grants as pay_period_forecast). Nothing here writes a table.

create or replace function public.daily_balance_forecast(p_periods integer default 7, p_lookahead integer default 6)
returns table (
  day               date,
  projected_balance numeric,
  income_total      numeric,
  outflow_total     numeric,
  event_count       integer,
  events            jsonb,
  is_today          boolean,
  cash_as_of        date
)
language sql
stable
set search_path = ''
as $function$
  with cfg as (
    select public.app_today() as today
  ),
  cash as (
    -- identical to pay_period_forecast.cash
    select coalesce(sum(ab.estimated_balance), 0)
             - coalesce((select sum(greatest(pos.balance - pos.current_contribution, 0))
                           from public.set_asides sa
                           cross join lateral public.set_aside_position(sa.id) pos
                          where sa.is_active), 0)
             - coalesce((select sum(m.amount)
                           from public.envelope_moves m
                           join public.envelopes e on e.id = m.envelope_id
                          where e.is_active), 0) as bal,
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
    select s.k, s.pay_date, s.nxt, p.items
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
           it->>'status' as status,
           coalesce((it->>'overdue')::boolean, false) as overdue,
           coalesce((it->>'projected')::boolean, false) as projected,
           it->>'occurrence_id' as occurrence_id,
           coalesce((it->>'date')::date, pr.pay_date) as item_date,
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
  horizon as (
    -- last day covered by the p_periods periods pay_period_forecast returns
    select max(pr.nxt) - 1 as last_day from periods pr where pr.k <= p_periods
  ),
  days as (
    select g::date as day
    from cfg, horizon h, generate_series(cfg.today, h.last_day, interval '1 day') g
  ),
  daily as (
    select d.day,
           coalesce(sum(e.amount), 0) as net,
           coalesce(sum(e.amount) filter (where e.amount > 0), 0) as income_total,
           coalesce(-sum(e.amount) filter (where e.amount < 0), 0) as outflow_total,
           count(e.kind)::int as event_count,
           coalesce(jsonb_agg(jsonb_build_object(
                      'type', e.kind, 'name', e.name, 'amount', e.amount, 'status', e.status,
                      'overdue', e.overdue, 'projected', e.projected,
                      'occurrence_id', e.occurrence_id, 'item_date', e.item_date)
                    order by case when e.amount >= 0 then 0 else 1 end, e.name)
                    filter (where e.kind is not null), '[]'::jsonb) as events
    from days d
    left join ev e on e.ev_date = d.day and not e.received
    group by d.day
  )
  select d.day,
         round(cash.bal + sum(d.net) over (order by d.day), 2),
         round(d.income_total, 2),
         round(d.outflow_total, 2),
         d.event_count,
         d.events,
         d.day = cfg.today,
         cash.as_of
  from daily d
  cross join cfg
  cross join cash
  order by d.day;
$function$;

comment on function public.daily_balance_forecast(integer, integer) is
  'One row per day from today to the end of the forecast horizon: end-of-day spendable balance and that day''s scheduled paychecks, bills, minimums, set-asides and plan payments. Same events and cash base as pay_period_forecast; scheduled items only.';

revoke all on function public.daily_balance_forecast(integer, integer) from public, anon;
grant execute on function public.daily_balance_forecast(integer, integer) to authenticated, service_role;

create view public.v_daily_balance_forecast with (security_invoker = true) as
  select * from public.daily_balance_forecast();

revoke all on public.v_daily_balance_forecast from anon, public;
grant select on public.v_daily_balance_forecast to authenticated;
