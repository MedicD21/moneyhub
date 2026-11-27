-- Adds safe_to_spend to the calendar view: the most that could be spent on or after a given day without the
-- projected balance dropping below the low-balance floor at any later point in the forecast horizon.
-- Null when there is nothing safe to spend (balance dips to or below the floor on or after that day).
-- View-only change: same columns, one new column at the end. No table, function or grant changes.

create or replace view public.v_daily_balance_forecast with (security_invoker = true) as
  select d.day,
         d.projected_balance,
         d.income_total,
         d.outflow_total,
         d.event_count,
         d.events,
         d.is_today,
         d.cash_as_of,
         case
           when d.lowest_ahead - d.floor > 0 then round(d.lowest_ahead - d.floor, 2)
         end as safe_to_spend
  from (
    select f.*,
           min(f.projected_balance) over (order by f.day desc) as lowest_ahead,
           coalesce((select s.low_balance_threshold from public.app_settings s limit 1), 0) as floor
    from public.daily_balance_forecast() f
  ) d
  order by d.day;

alter view public.v_daily_balance_forecast set (security_invoker = true);
revoke all on public.v_daily_balance_forecast from anon, public;
grant select on public.v_daily_balance_forecast to authenticated;

comment on view public.v_daily_balance_forecast is
  'daily_balance_forecast() as a view. safe_to_spend = lowest projected balance from this day to the end of the horizon, minus app_settings.low_balance_threshold; null when not positive.';
