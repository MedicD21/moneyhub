-- One "Pays" link (migration 20261113010000_single_pays_link.sql): the database decides transactions.debt_id.
--   * a bill that is a debt's payment schedule sets debt_id from the bill
--   * a different p_debt_id for that bill is rejected
--   * a bill with no debt leaves debt_id null (unless a debt is passed explicitly, as before)
--   * an extra payment with no bill still takes a debt_id
-- Today is 2026-03-10.
begin;
create extension if not exists pgtap with schema extensions;
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans, public.envelopes cascade;
grant execute on all functions in schema extensions to anon, authenticated;
select plan(17);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-10';

insert into public.accounts (id, name, kind) values ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking');
insert into public.debts (id, name, kind, apr, min_payment, due_day) values
  ('d0000000-0000-0000-0000-000000000001', 'Visa', 'credit_card', 24.99, 35, 12),
  ('d0000000-0000-0000-0000-000000000002', 'Car loan', 'auto', 6.9, 300, 17);
insert into public.bills (id, name, amount, frequency, due_day, debt_id) values
  ('e0000000-0000-0000-0000-000000000001', 'Visa payment', 35, 'monthly', 12, 'd0000000-0000-0000-0000-000000000001'),
  ('e0000000-0000-0000-0000-000000000002', 'Water', 100, 'monthly', 20, null);
select public.ensure_bill_occurrences('2026-03-31');

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- (before any payment is linked: linking a bill marks it paid, which removes it from the view)
select ok(exists (select 1 from public.v_upcoming_bills where bill_name = 'Visa payment'
                    and debt_id = 'd0000000-0000-0000-0000-000000000001'),
          'v_upcoming_bills exposes debt_id for the sheet');

-- ---- add_manual_transaction ----
select lives_ok(
  $$select public.add_manual_transaction(-35, '2026-03-09', 'Visa bill only', null, null, null, false,
      (select id from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000001' limit 1))$$,
  'add: a debt bill alone is accepted');
select is((select debt_id from public.transactions where merchant = 'Visa bill only'),
          'd0000000-0000-0000-0000-000000000001'::uuid, 'add: a debt bill sets debt_id from the bill');
select lives_ok(
  $$select public.add_manual_transaction(-35, '2026-03-09', 'Visa bill matching', null, null, null, false,
      (select id from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000001' limit 1),
      'd0000000-0000-0000-0000-000000000001')$$,
  'add: a debt bill with the same debt is accepted');
select is((select debt_id from public.transactions where merchant = 'Visa bill matching'),
          'd0000000-0000-0000-0000-000000000001'::uuid, 'add: matching debt keeps the bill''s debt_id');
select throws_ok(
  $$select public.add_manual_transaction(-35, '2026-03-09', 'Visa bill conflict', null, null, null, false,
      (select id from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000001' limit 1),
      'd0000000-0000-0000-0000-000000000002')$$,
  'P0001', 'That bill pays a different debt than the one selected', 'add: a conflicting debt_id is rejected');
select is((select count(*)::int from public.transactions where merchant = 'Visa bill conflict'), 0,
          'add: nothing is stored for the conflict');
select lives_ok(
  $$select public.add_manual_transaction(-100, '2026-03-09', 'Water only', null, null, null, false,
      (select id from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000002' limit 1))$$,
  'add: a non-debt bill is accepted');
select is((select debt_id from public.transactions where merchant = 'Water only'), null::uuid,
          'add: a non-debt bill leaves debt_id null');
select lives_ok(
  $$select public.add_manual_transaction(-50, '2026-03-09', 'Extra Car', null, null, null, false, null,
      'd0000000-0000-0000-0000-000000000002')$$,
  'add: an extra payment with no bill is accepted');
select results_eq(
  $$select debt_id, bill_occurrence_id from public.transactions where merchant = 'Extra Car'$$,
  $$values ('d0000000-0000-0000-0000-000000000002'::uuid, null::uuid)$$,
  'add: an extra payment takes the debt_id it was given');
select throws_ok(
  $$select public.add_manual_transaction(35, '2026-03-09', 'Visa refund', null, null, null, false,
      (select id from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000001' limit 1))$$,
  'P0001', 'A bill payment must be money going out', 'add: a debt bill still needs money out');

-- ---- update_manual_transaction ----
select lives_ok(
  $$select public.update_manual_transaction((select id from public.transactions where merchant = 'Water only'),
      -35, '2026-03-09', 'Water only', null, null, false,
      (select id from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000001' limit 1))$$,
  'update: switching to a debt bill is accepted');
select is((select debt_id from public.transactions where merchant = 'Water only'),
          'd0000000-0000-0000-0000-000000000001'::uuid, 'update: a debt bill sets debt_id from the bill');
select throws_ok(
  $$select public.update_manual_transaction((select id from public.transactions where merchant = 'Water only'),
      -35, '2026-03-09', 'Water only', null, null, false,
      (select id from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000001' limit 1),
      'd0000000-0000-0000-0000-000000000002')$$,
  'P0001', 'That bill pays a different debt than the one selected', 'update: a conflicting debt_id is rejected');
select lives_ok(
  $$select public.update_manual_transaction((select id from public.transactions where merchant = 'Water only'),
      -100, '2026-03-09', 'Water only', null, null, false,
      (select id from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000002' limit 1))$$,
  'update: switching to a non-debt bill is accepted');
select is((select debt_id from public.transactions where merchant = 'Water only'), null::uuid,
          'update: a non-debt bill clears debt_id');
select * from finish();
rollback;
