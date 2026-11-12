-- Phase 1: v_balance_check and v_account_balances
begin;
create extension if not exists pgtap with schema extensions;
-- Start from empty tables (rolled back with the test), so the suite also runs on a seeded DB.
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans cascade;
select plan(9);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-10';

insert into public.accounts (id, name, kind) values
  ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking'),
  ('a0000000-0000-0000-0000-000000000002', 'Visa',     'credit_card');

-- Checking: consistent data
insert into public.balance_snapshots (id, account_id, as_of_date, balance) values
  ('50000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '2026-03-01', 1000.00);
insert into public.transactions (account_id, txn_date, description_raw, amount) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-01', 'ALREADY IN BALANCE', -99.00),  -- on the snapshot date: excluded
  ('a0000000-0000-0000-0000-000000000001', '2026-03-02', 'KROGER', -50.00),
  ('a0000000-0000-0000-0000-000000000001', '2026-03-03', 'PAYROLL', 200.00),
  ('a0000000-0000-0000-0000-000000000001', '2026-03-04', 'SHELL', -25.25);
insert into public.balance_snapshots (id, account_id, as_of_date, balance) values
  ('50000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', '2026-03-04', 1124.75);

select is((select count(*)::int from public.v_balance_check where account_id = 'a0000000-0000-0000-0000-000000000001'),
          1, 'the first snapshot has nothing to compare against');
select results_eq(
  $$select expected_balance, actual_balance, difference, likely_cause
      from public.v_balance_check where snapshot_id = '50000000-0000-0000-0000-000000000002'$$,
  $$values (1124.75::numeric, 1124.75::numeric, 0::numeric, 'ok'::text)$$,
  'consistent data -> difference 0');

-- A $50 transaction on 03-05 was never logged; a pending $10 exists (bank balance excludes pending).
insert into public.transactions (account_id, txn_date, description_raw, amount, status) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-05', 'SQ *COFFEE', -10.00, 'pending');
insert into public.balance_snapshots (id, account_id, as_of_date, balance) values
  ('50000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', '2026-03-06', 1074.75);

select results_eq(
  $$select expected_balance, actual_balance, difference, pending_between
      from public.v_balance_check where snapshot_id = '50000000-0000-0000-0000-000000000003'$$,
  $$values (1124.75::numeric, 1074.75::numeric, -50.00::numeric, -10.00::numeric)$$,
  'missing $50 row -> difference -50.00 (pending excluded, reported separately)');
select ok((select is_latest from public.v_balance_check where snapshot_id = '50000000-0000-0000-0000-000000000003'),
          'latest snapshot is flagged');

-- Logging the missing row fixes the check
insert into public.transactions (account_id, txn_date, description_raw, amount) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-05', 'MISSED ROW', -50.00);
select is((select difference from public.v_balance_check where snapshot_id = '50000000-0000-0000-0000-000000000003'),
          0::numeric, 'adding the missing transaction brings the difference to 0');

-- Account balance estimate: last snapshot + posted after + outstanding pending
insert into public.transactions (account_id, txn_date, description_raw, amount) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-08', 'TARGET', -30.00);
select results_eq(
  $$select last_snapshot_balance, estimated_balance, pending_total, days_since_screenshot
      from public.v_account_balances where account_id = 'a0000000-0000-0000-0000-000000000001'$$,
  $$values (1074.75::numeric, 1034.75::numeric, -10.00::numeric, 4)$$,
  'estimated balance = 1074.75 - 30 (posted after) - 10 (pending)');

-- Credit card: balances stored as displayed (owed = positive)
insert into public.balance_snapshots (account_id, as_of_date, balance) values
  ('a0000000-0000-0000-0000-000000000002', '2026-03-01', 500.00);
insert into public.transactions (account_id, txn_date, description_raw, amount) values
  ('a0000000-0000-0000-0000-000000000002', '2026-03-02', 'AMAZON', -40.00),
  ('a0000000-0000-0000-0000-000000000002', '2026-03-03', 'PAYMENT THANK YOU', 100.00);
insert into public.balance_snapshots (id, account_id, as_of_date, balance) values
  ('50000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000002', '2026-03-04', 440.00);
select is((select difference from public.v_balance_check where snapshot_id = '50000000-0000-0000-0000-000000000004'),
          0::numeric, 'credit card: owed 500, +40 purchase, -100 payment = owed 440 -> difference 0');

insert into public.transactions (account_id, txn_date, description_raw, amount) values
  ('a0000000-0000-0000-0000-000000000002', '2026-03-05', 'NETFLIX', -15.49);
select results_eq(
  $$select estimated_balance, estimated_balance_display, is_liability
      from public.v_account_balances where account_id = 'a0000000-0000-0000-0000-000000000002'$$,
  $$values (-455.49::numeric, 455.49::numeric, true)$$,
  'credit card estimate: signed -455.49, displayed as 455.49 owed');

-- Bank whose displayed balance includes pending
update public.accounts set balance_includes_pending = true where id = 'a0000000-0000-0000-0000-000000000001';
delete from public.transactions where description_raw = 'MISSED ROW';
select is((select difference from public.v_balance_check where snapshot_id = '50000000-0000-0000-0000-000000000003'),
          -40.00::numeric, 'balance_includes_pending counts pending rows in the window');

select * from finish();
rollback;
