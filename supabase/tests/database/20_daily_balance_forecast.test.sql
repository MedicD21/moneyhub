-- daily_balance_forecast / v_daily_balance_forecast (migration 20261127000000_daily_balance_forecast.sql).
--
-- Today 2026-03-10. Biweekly pay $2,000 anchored Fri 2026-03-06; the 03-06 paycheck is already deposited
-- (PAYROLL txn), so it must not be counted again. Checking snapshot 1000.00 on 03-09.
-- Horizon with (p_periods 2, p_lookahead 1): 03-10 .. 04-02 = 24 days.
--
--   Gym        40  due 03-05  unpaid, overdue -> lands on today (03-10)
--   Streaming  15  due 03-01  unpaid, overdue -> lands on today (03-10); 04-01 is projected (no occurrence row)
--   Rent     1200  due 03-15  generated occurrence
--   Internet   70  due 03-25  generated occurrence
--   Car ins  1800  due 03-27  annual, projected (no occurrence row)
--   Payday 03-20  +2000
--
--   03-10  1000 - 40 - 15       =   945
--   03-15   945 - 1200          =  -255   (lowest point)
--   03-20  -255 + 2000          =  1745
--   03-25  1745 - 70            =  1675
--   03-27  1675 - 1800          =  -125
--   04-01  -125 - 15            =  -140
begin;
create extension if not exists pgtap with schema extensions;
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans, public.envelopes cascade;
grant execute on all functions in schema extensions to anon, authenticated;
select plan(15);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-10';

insert into public.accounts (id, name, kind) values ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking');
insert into public.balance_snapshots (account_id, as_of_date, balance) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-09', 1000);
insert into public.income_sources (name, frequency, anchor_date, expected_net, deposit_account_id) values
  ('Job', 'biweekly', '2026-03-06', 2000, 'a0000000-0000-0000-0000-000000000001');
insert into public.transactions (account_id, txn_date, description_raw, amount, category_id) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-06', 'PAYROLL', 2000, (select id from public.categories where name = 'Income'));

insert into public.bills (id, name, amount, is_variable, frequency, due_day, anchor_date) values
  ('e0000000-0000-0000-0000-000000000001', 'Rent',          1200, false, 'monthly', 15, null),
  ('e0000000-0000-0000-0000-000000000002', 'Gym',             40, false, 'monthly',  5, null),
  ('e0000000-0000-0000-0000-000000000003', 'Internet',        70, false, 'monthly', 25, null),
  ('e0000000-0000-0000-0000-000000000004', 'Car insurance', 1800, false, 'annual', null, '2025-03-27'),
  ('e0000000-0000-0000-0000-000000000005', 'Streaming',       15, false, 'monthly',  1, null);
select public.ensure_bill_occurrences('2026-03-31');

select is((select count(*)::int from public.daily_balance_forecast(2, 1)), 24, 'one row per day from today to the end of the horizon');
select results_eq(
  $$select day, projected_balance, is_today from public.daily_balance_forecast(2, 1) order by day limit 1$$,
  $$values ('2026-03-10'::date, 945.00::numeric, true)$$,
  'today: cash 1000 minus the two overdue bills (Gym, Streaming) that land on today');
select is((select projected_balance from public.daily_balance_forecast(2, 1) where day = '2026-03-14'), 945.00::numeric,
          'days without events carry the balance forward');
select is((select projected_balance from public.daily_balance_forecast(2, 1) where day = '2026-03-15'), -255.00::numeric,
          'rent day drops the balance');
select results_eq(
  $$select projected_balance, income_total, outflow_total from public.daily_balance_forecast(2, 1) where day = '2026-03-20'$$,
  $$values (1745.00::numeric, 2000.00::numeric, 0.00::numeric)$$,
  'payday adds the paycheck');
select is((select projected_balance from public.daily_balance_forecast(2, 1) where day = '2026-03-25'), 1675.00::numeric,
          'a generated occurrence (Internet) is subtracted');
select is((select projected_balance from public.daily_balance_forecast(2, 1) where day = '2026-03-27'), -125.00::numeric,
          'an annual bill with no occurrence row is projected from the bill');
select results_eq(
  $$select projected_balance, (e->>'projected')::boolean, e->>'occurrence_id' is null
      from public.daily_balance_forecast(2, 1) d, jsonb_array_elements(d.events) e
     where d.day = '2026-04-01' and e->>'name' = 'Streaming'$$,
  $$values (-140.00::numeric, true, true)$$,
  'a projected bill is flagged projected and has no occurrence id');
select results_eq(
  $$select (e->>'overdue')::boolean, (e->>'item_date')::date
      from public.daily_balance_forecast(2, 1) d, jsonb_array_elements(d.events) e
     where d.day = '2026-03-10' and e->>'name' = 'Gym'$$,
  $$values (true, '2026-03-05'::date)$$,
  'an overdue bill lands on today, flagged overdue, and keeps its original due date');
select is((select coalesce(sum(income_total), 0) from public.daily_balance_forecast(2, 1) where day < '2026-03-20'), 0.00::numeric,
          'the paycheck already deposited on 03-06 is not counted again');

-- must agree with the forecast: on every forecast binding date, the calendar balance is the binding balance
select ok(
  (select count(*) > 0 and bool_and(d.projected_balance = f.binding_balance)
     from public.pay_period_forecast(2, 1) f
     join public.daily_balance_forecast(2, 1) d on d.day = f.binding_date),
  'calendar balance on each forecast binding date equals pay_period_forecast.binding_balance');
select is((select projected_balance from public.daily_balance_forecast(2, 1) where day = '2026-03-15'),
          (select min(binding_balance) from public.pay_period_forecast(2, 1)),
          'the lowest forecast point shows up on the calendar');

-- a skipped bill drops out
update public.bill_occurrences set status = 'skipped'
 where bill_id = 'e0000000-0000-0000-0000-000000000001';
select is((select projected_balance from public.daily_balance_forecast(2, 1) where day = '2026-03-15'), 945.00::numeric,
          'a skipped bill is not subtracted');

-- the signed-in owner can read the view; anonymous cannot
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select is((select projected_balance from public.v_daily_balance_forecast where day = '2026-03-15'), 945.00::numeric,
          'authenticated owner reads the view (default horizon)');
reset role;
select ok(not has_table_privilege('anon', 'public.v_daily_balance_forecast', 'select')
          and not has_function_privilege('anon', 'public.daily_balance_forecast(integer,integer)', 'execute'),
          'anon cannot read the view or call the function');

select * from finish();
rollback;
