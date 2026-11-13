-- Shortfall hint: roughly how many extra overtime hours would close a shortfall.
-- extra_hour_net is the approximate take-home per extra overtime hour (35.70 gross OT rate x ~0.75
-- after PERS, federal, state and Medicare, fitted to the Nov 2026 paystubs). Edit it in app_settings
-- if the rate or withholding changes.
alter table public.app_settings
  add column if not exists extra_hour_net   numeric not null default 26.80 check (extra_hour_net > 0),
  add column if not exists extra_shift_hours integer not null default 24   check (extra_shift_hours > 0);

create or replace view public.v_pay_period_forecast with (security_invoker = true) as
select f.period_index, f.period_start, f.period_end, f.next_pay_date, f.is_current, f.expected_net, f.income_in,
       f.obligations, f.starting_cash, f.cash_as_of, f.low_balance_floor, f.safe_to_spend, f.max_safe_to_spend,
       f.hold_for_later, f.carry_out, f.binding_date, f.binding_balance, f.shortfall, f.income_received,
       f.cash_before_spending, f.next_income, f.next_obligations, f.next_draw, f.next_period_end,
       s.extra_hour_net,
       case when f.shortfall then ceil(-f.safe_to_spend / s.extra_hour_net * 2) / 2 end as extra_hours_needed,
       case when f.shortfall then round(s.extra_hour_net * s.extra_shift_hours, 2) end as extra_shift_net,
       s.extra_shift_hours
from public.pay_period_forecast() f
cross join (select a.extra_hour_net, a.extra_shift_hours from public.app_settings a where a.id) s;
