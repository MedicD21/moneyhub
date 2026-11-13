-- Paid county holidays flow into the paycheck forecast.
-- A holiday is paid on the paycheck whose pay period contains it. Pay periods are 14 days and end
-- app_settings.pay_period_end_before_deposit_days (5) days before the Envelope deposit
-- (period ends Friday, EFT the following Friday, deposit 2 days earlier). Inferred from the Nov 11
-- Veterans Day holiday landing on the Nov 25 deposit; confirm against a stub.
-- Net pay per holiday hour = $23.80 base rate x ~0.75 after PERS, federal, state and Medicare.
-- A paycheck with an actual_net override is left alone (the override already is the real amount).
-- Dates are the COUNTY-observed holiday dates from the Delaware County 2026/2027 schedules;
-- seeded from Veterans Day 2026 forward so already-paid checks are unchanged.
alter table public.app_settings
  add column if not exists holiday_hour_net numeric not null default 17.86 check (holiday_hour_net >= 0),
  add column if not exists pay_period_end_before_deposit_days integer not null default 5 check (pay_period_end_before_deposit_days between 0 and 13);

create table public.paid_holidays (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default public.app_owner_id(),
  holiday_date date not null,
  name text not null,
  hours numeric not null check (hours > 0 and hours <= 24),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, holiday_date)
);
comment on table public.paid_holidays is 'County-observed paid holidays. hours = holiday pay hours (8 full, 4 for half-day holidays). Added to the paycheck whose pay period contains the date (see holiday_pay_net).';
alter table public.paid_holidays enable row level security;
create policy "owner can read" on public.paid_holidays for select to authenticated
  using (owner_id = (select auth.uid()));
revoke all on public.paid_holidays from anon, authenticated;
grant select on public.paid_holidays to authenticated;
create trigger set_updated_at before update on public.paid_holidays
  for each row execute function public.set_updated_at();

create function public.holiday_pay_net(p_pay_date date)
 returns numeric
 language sql
 stable
 set search_path to ''
as $function$
  select coalesce(round(sum(h.hours) * (select s.holiday_hour_net from public.app_settings s where s.id), 2), 0)
  from public.paid_holidays h
  where h.holiday_date between p_pay_date - (13 + (select s.pay_period_end_before_deposit_days from public.app_settings s where s.id))
                           and p_pay_date - (select s.pay_period_end_before_deposit_days from public.app_settings s where s.id);
$function$;
revoke all on function public.holiday_pay_net(date) from public, anon;
grant execute on function public.holiday_pay_net(date) to authenticated, service_role;

create or replace function public.pay_dates(p_start date, p_end date)
 returns table(income_source_id uuid, pay_date date, expected_net numeric)
 language sql
 stable
 rows 30
 set search_path to ''
as $function$
  select s.id, coalesce(ov.actual_date, adj.pay_date),
         coalesce(ov.actual_net, s.expected_net + public.holiday_pay_net(coalesce(ov.actual_date, adj.pay_date)))
  from public.income_sources s
  cross join lateral (
    -- widen by 10 days: weekend shifts and overrides can move a date into/out of range
    select public.adjust_business_day(r, s.weekend_adjust) as pay_date
    from public.recurring_dates(
           s.frequency, s.anchor_date,
           case when s.frequency = 'semimonthly' then s.semimonthly_days end,
           p_start - 10, p_end + 10) r
  ) adj
  left join public.pay_date_overrides ov
         on ov.income_source_id = s.id and ov.scheduled_date = adj.pay_date
  where s.is_active
    and coalesce(ov.actual_date, adj.pay_date) between p_start and p_end
    and coalesce(ov.actual_net, s.expected_net + public.holiday_pay_net(coalesce(ov.actual_date, adj.pay_date))) > 0
  order by 2, s.name;
$function$;

insert into public.paid_holidays (holiday_date, name, hours) values
  ('2026-11-11', 'Veterans Day', 8),
  ('2026-11-26', 'Thanksgiving Day', 8),
  ('2026-11-27', 'Day after Thanksgiving', 8),
  ('2026-12-24', 'Christmas Eve', 4),
  ('2026-12-25', 'Christmas Day', 8),
  ('2027-01-01', 'New Year''s Day', 8),
  ('2027-01-18', 'Martin Luther King Day', 8),
  ('2027-02-15', 'President''s Day', 8),
  ('2027-05-31', 'Memorial Day', 8),
  ('2027-06-18', 'Juneteenth (county observed)', 8),
  ('2027-07-05', 'Independence Day (county observed)', 8),
  ('2027-09-06', 'Labor Day', 8),
  ('2027-09-23', 'Little Brown Jug Day', 4),
  ('2027-11-11', 'Veterans Day', 8),
  ('2027-11-25', 'Thanksgiving Day', 8),
  ('2027-11-26', 'Day after Thanksgiving', 8),
  ('2027-12-23', 'Christmas Eve (county observed)', 4),
  ('2027-12-24', 'Christmas Day (county observed)', 8);
