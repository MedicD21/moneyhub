-- Phase 1: pay_dates()
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');

-- 2026-01-02 is a Friday.
insert into public.income_sources (id, name, frequency, anchor_date, expected_net) values
  ('c0000000-0000-0000-0000-000000000001', 'Job', 'biweekly', '2026-01-02', 2000);

select results_eq(
  $$select pay_date from public.pay_dates('2026-01-01', '2026-02-28')$$,
  $$values ('2026-01-02'::date), ('2026-01-16'), ('2026-01-30'), ('2026-02-13'), ('2026-02-27')$$,
  'biweekly steps 14 days from the anchor');

select results_eq(
  $$select date_trunc('month', pay_date)::date from public.pay_dates('2026-01-01', '2026-12-31')
    group by 1 having count(*) = 3 order by 1$$,
  $$values ('2026-01-01'::date), ('2026-07-01')$$,
  'biweekly 3-paycheck months in 2026 are January and July');

select is((select count(*)::int from public.pay_dates('2026-01-01', '2026-12-31')), 26,
          '26 biweekly paydays in 2026');

update public.income_sources set anchor_date = '2026-06-05';
select results_eq(
  $$select pay_date from public.pay_dates('2026-01-01', '2026-01-31')$$,
  $$values ('2026-01-02'::date), ('2026-01-16'), ('2026-01-30')$$,
  'an anchor in the future generates the same past schedule');

-- Semimonthly 15th + 31st (31 = last day of month)
update public.income_sources set frequency = 'semimonthly', semimonthly_days = '{15,31}', anchor_date = '2026-01-15';
select results_eq(
  $$select pay_date from public.pay_dates('2026-02-01', '2026-04-30')$$,
  $$values ('2026-02-15'::date), ('2026-02-28'), ('2026-03-15'), ('2026-03-31'), ('2026-04-15'), ('2026-04-30')$$,
  'semimonthly clamps day 31 to Feb 28 and Apr 30');
select results_eq(
  $$select pay_date from public.pay_dates('2028-02-01', '2028-02-29')$$,
  $$values ('2028-02-15'::date), ('2028-02-29')$$,
  'semimonthly clamps day 31 to Feb 29 in a leap year');

-- Weekend adjustment: 2026-02-15 is a Sunday, 2026-02-28 is a Saturday.
update public.income_sources set weekend_adjust = 'previous_business_day';
select results_eq(
  $$select pay_date from public.pay_dates('2026-02-01', '2026-02-28')$$,
  $$values ('2026-02-13'::date), ('2026-02-27')$$,
  'previous_business_day moves weekend paydays to Friday');

-- Monthly on the 31st
update public.income_sources set frequency = 'monthly', semimonthly_days = null,
       anchor_date = '2026-01-31', weekend_adjust = 'none';
select results_eq(
  $$select pay_date from public.pay_dates('2026-02-01', '2026-04-30')$$,
  $$values ('2026-02-28'::date), ('2026-03-31'), ('2026-04-30')$$,
  'monthly on the 31st clamps to month end');

update public.income_sources set is_active = false;
select is((select count(*)::int from public.pay_dates('2026-01-01', '2026-12-31')), 0,
          'inactive income sources produce no paydays');

select * from finish();
rollback;
