-- Phase 1: paycheck_plan() vs a hand-computed example, plus a shortfall case.
--
-- Today 2026-03-10. Biweekly pay $2,000 anchored Fri 2026-03-06, so the
-- current period is 2026-03-06 .. 2026-03-19 (next payday 2026-03-20).
--
-- Bills in the current period:
--   Rent       1200.00  due 03-15  unpaid                     -> 1200.00
--   Phone        80.00  due 03-08  paid by a linked txn        ->    0
--   Electric    120.00  due 03-18  variable, partial 50 paid   ->   70.00
--   Streaming    15.00  due 03-01  unpaid, overdue (carried in)->   15.00
--   Internet     70.00  due 03-25  next period                 ->    0
--                                                     bills    = 1285.00
-- Debt minimums:
--   Visa      35 due 12th, balance 1000, nothing paid           ->   35.00
--   Car loan 300 due 17th, 300 paid 03-05 (linked debt_id)      ->    0
--   Student   50 due 22nd -> next period                        ->    0
--                                                     minimums =   35.00
-- Set-asides: 100 + 50                                         =  150.00
-- Extra debt: plan extra_monthly 260 x 12 / 26 paydays          =  120.00
-- safe_to_spend = 2000 - 1285 - 35 - 150 - 120                  =  410.00
-- Spending since 03-06 through today (not bills/debts/transfers):
--   groceries 60 + dining 25.50 + uncategorized 4.50 - refund 10 =   80.00
-- remaining_safe_to_spend = 410 - 80                            =  330.00
--
-- Next period 2026-03-20 .. 2026-04-02:
--   Internet 70 (03-25) + Car insurance 1800 (annual, 03-27)
--   + Streaming 15 (04-01, projected: no occurrence row yet)     = 1885.00
--   Student minimum 50 (03-22)                                  =   50.00
--   safe = 2000 - 1885 - 50 - 150 - 120                         = -205.00 (shortfall)
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-10';

insert into public.accounts (id, name, kind) values
  ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking');

insert into public.income_sources (name, frequency, anchor_date, expected_net, deposit_account_id) values
  ('Job', 'biweekly', '2026-03-06', 2000, 'a0000000-0000-0000-0000-000000000001');

insert into public.bills (id, name, amount, is_variable, frequency, due_day, anchor_date) values
  ('e0000000-0000-0000-0000-000000000001', 'Rent',          1200, false, 'monthly', 15, null),
  ('e0000000-0000-0000-0000-000000000002', 'Phone',           80, false, 'monthly',  8, null),
  ('e0000000-0000-0000-0000-000000000003', 'Electric',       120, true,  'monthly', 18, null),
  ('e0000000-0000-0000-0000-000000000004', 'Streaming',       15, false, 'monthly',  1, null),
  ('e0000000-0000-0000-0000-000000000005', 'Internet',        70, false, 'monthly', 25, null),
  ('e0000000-0000-0000-0000-000000000006', 'Car insurance', 1800, false, 'annual', null, '2025-03-27');
select public.ensure_bill_occurrences('2026-03-31');

insert into public.debts (id, name, kind, apr, min_payment, due_day) values
  ('d0000000-0000-0000-0000-000000000001', 'Visa',     'credit_card', 24.99,  35, 12),
  ('d0000000-0000-0000-0000-000000000002', 'Car loan', 'auto',         6.90, 300, 17),
  ('d0000000-0000-0000-0000-000000000003', 'Student',  'student',      5.50,  50, 22);
insert into public.debt_balances (debt_id, as_of_date, balance) values
  ('d0000000-0000-0000-0000-000000000001', '2026-03-01', 1000);

insert into public.set_asides (name, per_paycheck) values ('Emergency fund', 100), ('Buffer', 50);
insert into public.debt_plans (name, strategy, extra_monthly, assumptions, summary, schedule, balances_as_of, is_active)
values ('Avalanche', 'avalanche', 260, '{}', '{}', '[]', '2026-03-01', true);

-- Transactions
insert into public.transactions (id, account_id, txn_date, description_raw, amount, category_id, debt_id) values
  ('70000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '2026-03-06', 'PAYROLL', 2000,
     (select id from public.categories where name = 'Income'), null),
  ('70000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', '2026-03-07', 'KROGER', -60,
     (select id from public.categories where name = 'Groceries'), null),
  ('70000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', '2026-03-09', 'CHIPOTLE', -25.50,
     (select id from public.categories where name = 'Dining'), null),
  ('70000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', '2026-03-08', 'VERIZON', -80,
     (select id from public.categories where name = 'Phone/Internet'), null),
  ('70000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', '2026-03-09', 'TO SAVINGS', -500,
     (select id from public.categories where name = 'Transfer'), null),
  ('70000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001', '2026-03-05', 'ALLY AUTO', -300,
     (select id from public.categories where name = 'Debt Payment'), 'd0000000-0000-0000-0000-000000000002'),
  ('70000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000001', '2026-03-11', 'FUTURE', -10,
     (select id from public.categories where name = 'Misc'), null),
  ('70000000-0000-0000-0000-000000000008', 'a0000000-0000-0000-0000-000000000001', '2026-03-10', 'UNKNOWN', -4.50,
     null, null),
  ('70000000-0000-0000-0000-000000000009', 'a0000000-0000-0000-0000-000000000001', '2026-03-09', 'KROGER REFUND', 10,
     (select id from public.categories where name = 'Groceries'), null);

select public.mark_bill_paid(
  (select id from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000002' and due_date = '2026-03-08'),
  '70000000-0000-0000-0000-000000000004');
update public.bill_occurrences set status = 'partial', paid_amount = 50, paid_date = '2026-03-09'
 where bill_id = 'e0000000-0000-0000-0000-000000000003' and due_date = '2026-03-18';

-- Current period
select results_eq(
  $$select period_start, period_end, next_pay_date, is_current from public.paycheck_plan()$$,
  $$values ('2026-03-06'::date, '2026-03-19'::date, '2026-03-20'::date, true)$$,
  'current period is the latest payday <= today until the next payday');
select results_eq(
  $$select expected_net, bills_total, minimums_total, set_asides_total, extra_debt from public.paycheck_plan()$$,
  $$values (2000.00::numeric, 1285.00::numeric, 35.00::numeric, 150.00::numeric, 120.00::numeric)$$,
  'components match the hand-computed example');
select results_eq(
  $$select safe_to_spend, shortfall from public.paycheck_plan()$$,
  $$values (410.00::numeric, false)$$,
  'safe_to_spend = 2000 - 1285 - 35 - 150 - 120 = 410');
select results_eq(
  $$select spent_so_far, remaining_safe_to_spend from public.paycheck_plan()$$,
  $$values (80.00::numeric, 330.00::numeric)$$,
  'spent_so_far ignores bills, debt payments, transfers, income and future-dated rows; refunds reduce it');
select results_eq(
  $$select i->>'name', (i->>'amount')::numeric, (i->>'overdue')::boolean
      from public.paycheck_plan() pp, jsonb_array_elements(pp.items) i
     where i->>'type' = 'bill' order by i->>'date'$$,
  $$values ('Streaming'::text, 15.00::numeric, true), ('Rent', 1200.00, false), ('Electric', 70.00, false)$$,
  'itemized bills: overdue carried in, paid excluded, partial shows remainder');
select results_eq(
  $$select i->>'name' from public.paycheck_plan() pp, jsonb_array_elements(pp.items) i
     where i->>'type' = 'debt_minimum'$$,
  $$values ('Visa'::text)$$,
  'debt minimum already paid this cycle (car loan) is excluded');

-- Any date inside the period returns the same period
select is((select period_start from public.paycheck_plan('2026-03-19')), '2026-03-06'::date,
          'p_pay_date selects the period containing that date');

-- Next period: shortfall
select results_eq(
  $$select period_start, bills_total, minimums_total, safe_to_spend, shortfall, is_current, spent_so_far
      from public.paycheck_plan('2026-03-20')$$,
  $$values ('2026-03-20'::date, 1885.00::numeric, 50.00::numeric, -205.00::numeric, true, false, 0::numeric)$$,
  'next period: 2000 - 1885 - 50 - 150 - 120 = -205 -> shortfall');
select ok(
  exists(select 1 from public.paycheck_plan('2026-03-20') pp, jsonb_array_elements(pp.items) i
          where i->>'name' = 'Streaming' and (i->>'projected')::boolean and i->>'date' = '2026-04-01'),
  'bills beyond generated occurrences are projected from the bill schedule');

-- Overdue items are only carried into the current period
select ok(
  not exists(select 1 from public.paycheck_plan('2026-03-20') pp, jsonb_array_elements(pp.items) i
              where (i->>'overdue')::boolean),
  'future periods do not carry overdue bills');

-- v_pay_periods: -2..+6
select results_eq(
  $$select min(period_offset), max(period_offset), count(*)::int from public.v_pay_periods$$,
  $$values (-2, 6, 9)$$,
  'v_pay_periods returns 2 past, the current and 6 future periods');
select is((select safe_to_spend from public.v_pay_periods where period_offset = 0), 410.00::numeric,
          'v_pay_periods current row matches paycheck_plan()');

-- No income -> no plan rows (not an error)
update public.income_sources set is_active = false;
select is((select count(*)::int from public.paycheck_plan()), 0, 'no active income -> empty result');

select * from finish();
rollback;
