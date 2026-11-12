-- Phase 1: ensure_bill_occurrences()
begin;
create extension if not exists pgtap with schema extensions;
-- Start from empty tables (rolled back with the test), so the suite also runs on a seeded DB.
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans cascade;
select plan(11);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2027-01-15';

insert into public.bills (id, name, amount, frequency, due_day) values
  ('e0000000-0000-0000-0000-000000000001', 'Rent', 1200, 'monthly', 31);

select is(public.ensure_bill_occurrences('2027-03-31'), 3, 'creates Jan, Feb, Mar occurrences');
select is(public.ensure_bill_occurrences('2027-03-31'), 0, 'second run creates nothing (idempotent)');
select results_eq(
  $$select due_date from public.bill_occurrences order by due_date$$,
  $$values ('2027-01-31'::date), ('2027-02-28'), ('2027-03-31')$$,
  'due_day 31 clamps to Feb 28');
select is((select count(*)::int from public.bill_occurrences), 3, 'no duplicate rows after re-running');

set local app.today = '2028-02-01';
select public.ensure_bill_occurrences('2028-02-29');
select ok(exists(select 1 from public.bill_occurrences where due_date = '2028-02-29'),
          'due_day 31 clamps to Feb 29 in a leap year');

-- Quarterly / annual / biweekly
set local app.today = '2027-01-15';
insert into public.bills (id, name, amount, frequency, due_day, anchor_date) values
  ('e0000000-0000-0000-0000-000000000002', 'Water', 90, 'quarterly', 10, '2026-02-10'),
  ('e0000000-0000-0000-0000-000000000003', 'Amazon Prime', 139, 'annual', null, '2025-04-01'),
  ('e0000000-0000-0000-0000-000000000004', 'Daycare', 250, 'biweekly', null, '2027-01-08');
select public.ensure_bill_occurrences('2027-12-31');
select results_eq(
  $$select due_date from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000002' order by 1$$,
  $$values ('2027-02-10'::date), ('2027-05-10'), ('2027-08-10'), ('2027-11-10')$$,
  'quarterly follows the anchor month every 3 months');
select results_eq(
  $$select due_date from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000003'$$,
  $$values ('2027-04-01'::date)$$,
  'annual uses the anchor month and day');
select results_eq(
  $$select due_date from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000004'
     and due_date < '2027-02-15' order by 1$$,
  $$values ('2027-01-08'::date), ('2027-01-22'), ('2027-02-05')$$,
  'biweekly steps 14 days from the anchor');

-- Default horizon is today + 60
set local app.today = '2027-01-15';
insert into public.bills (id, name, amount, frequency, due_day) values
  ('e0000000-0000-0000-0000-000000000005', 'Gym', 30, 'monthly', 20);
select public.ensure_bill_occurrences();
select results_eq(
  $$select due_date from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000005' order by 1$$,
  $$values ('2027-01-20'::date), ('2027-02-20')$$,
  'default p_through is today + 60 days (2027-03-16), so 2027-03-20 is not created yet');

-- Bill amount change flows to future unpaid occurrences only
update public.bill_occurrences set status = 'paid', paid_amount = 30, paid_date = '2027-01-20'
 where bill_id = 'e0000000-0000-0000-0000-000000000005' and due_date = '2027-01-20';
update public.bills set amount = 35 where id = 'e0000000-0000-0000-0000-000000000005';
select results_eq(
  $$select due_date, expected_amount from public.bill_occurrences
     where bill_id = 'e0000000-0000-0000-0000-000000000005' order by 1$$,
  $$values ('2027-01-20'::date, 30.00::numeric), ('2027-02-20', 35.00)$$,
  'changing a bill amount updates future due occurrences, not paid history');

update public.bills set is_active = false where id = 'e0000000-0000-0000-0000-000000000005';
select results_eq(
  $$select due_date from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000005'$$,
  $$values ('2027-01-20'::date)$$,
  'deactivating a bill removes its future unpaid occurrences and keeps history');

select * from finish();
rollback;
