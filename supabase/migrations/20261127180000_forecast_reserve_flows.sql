-- Shows where the money "held back for later paychecks" goes, and where a paycheck's "taken from money held back
-- earlier" comes from. View-only change: v_pay_period_forecast keeps every existing column and gains four at the end.
--
-- Attribution rule (first in, first out): the reserve is a running pot (carry_out = previous carry_out + hold_for_later
-- from period 2 on, opening with the cash left over from the current period). Periods with hold_for_later > 0 pay into
-- it; later periods with hold_for_later < 0 draw from it, oldest money first.
-- The forecast math is unchanged: this only labels which paycheck's money funds which later period.
-- The current period (index 1) is never a draw (it starts from actual cash); its leftover cash is the opening reserve.

create or replace view public.v_pay_period_forecast with (security_invoker = true) as
with f as (
  select * from public.pay_period_forecast()
),
src0 as (
  -- The reserve starts with the cash left over from the current period (carry_out of period 1), then each later
  -- period with hold_for_later > 0 adds to it (carry_out = previous carry_out + hold_for_later from period 2 on).
  select f.period_index, f.period_start,
         case when f.period_index = 1 then f.carry_out else f.hold_for_later end as amt
  from f
  where (f.period_index = 1 and f.carry_out > 0) or (f.period_index > 1 and f.hold_for_later > 0)
),
src as (
  select s0.period_index, s0.period_start, s0.amt,
         sum(s0.amt) over (order by s0.period_index) - s0.amt as lo,
         sum(s0.amt) over (order by s0.period_index) as hi
  from src0 s0
),
drw as (
  select f.period_index, f.period_start, -f.hold_for_later as amt,
         sum(-f.hold_for_later) over (order by f.period_index) - (-f.hold_for_later) as lo,
         sum(-f.hold_for_later) over (order by f.period_index) as hi
  from f where f.hold_for_later < 0 and f.period_index > 1
),
flow as (
  select s.period_index as src_idx, s.period_start as src_date,
         d.period_index as drw_idx, d.period_start as drw_date,
         least(s.hi, d.hi) - greatest(s.lo, d.lo) as amt
  from src s
  join drw d on s.period_index < d.period_index
  where least(s.hi, d.hi) > greatest(s.lo, d.lo)
)
select f.period_index,
       f.period_start,
       f.period_end,
       f.next_pay_date,
       f.is_current,
       f.expected_net,
       f.income_in,
       f.obligations,
       f.starting_cash,
       f.cash_as_of,
       f.low_balance_floor,
       f.safe_to_spend,
       f.max_safe_to_spend,
       f.hold_for_later,
       f.carry_out,
       f.binding_date,
       f.binding_balance,
       f.shortfall,
       f.income_received,
       f.cash_before_spending,
       f.next_income,
       f.next_obligations,
       f.next_draw,
       f.next_period_end,
       s.extra_hour_net,
       case when f.shortfall then ceil((- f.safe_to_spend) / s.extra_hour_net * 2::numeric) / 2::numeric else null::numeric end as extra_hours_needed,
       case when f.shortfall then round(s.extra_hour_net * s.extra_shift_hours::numeric, 2) else null::numeric end as extra_shift_net,
       s.extra_shift_hours,
       -- where this period's held-back money goes: [{period_index, pay_date, amount}] (later periods it funds)
       coalesce((select jsonb_agg(jsonb_build_object('period_index', x.drw_idx, 'pay_date', x.drw_date, 'amount', round(x.amt, 2)) order by x.drw_idx)
                   from flow x where x.src_idx = f.period_index), '[]'::jsonb) as reserve_to,
       -- held back here (period 1: cash left over) but not needed by any draw inside the forecast window
       (select round(sr.amt - coalesce((select sum(x.amt) from flow x where x.src_idx = sr.period_index), 0), 2)
          from src sr where sr.period_index = f.period_index) as reserve_unassigned,
       -- where this period's draw comes from: [{period_index, pay_date, amount}] (earlier periods that funded it)
       coalesce((select jsonb_agg(jsonb_build_object('period_index', x.src_idx, 'pay_date', x.src_date, 'amount', round(x.amt, 2)) order by x.src_idx)
                   from flow x where x.drw_idx = f.period_index), '[]'::jsonb) as reserve_from,
       -- part of this period's draw that no earlier held-back money covers (should be 0)
       case when f.hold_for_later < 0 and f.period_index > 1
            then round(-f.hold_for_later - coalesce((select sum(x.amt) from flow x where x.drw_idx = f.period_index), 0), 2)
       end as reserve_unfunded
from f
cross join (
  select a.extra_hour_net, a.extra_shift_hours
  from public.app_settings a
  where a.id
) s;

alter view public.v_pay_period_forecast set (security_invoker = true);

comment on column public.v_pay_period_forecast.reserve_to is
  'Held-back money from this period assigned (first in, first out) to later periods that draw on it: [{period_index, pay_date, amount}].';
comment on column public.v_pay_period_forecast.reserve_from is
  'Earlier periods whose held-back money funds this period''s draw (first in, first out): [{period_index, pay_date, amount}].';
