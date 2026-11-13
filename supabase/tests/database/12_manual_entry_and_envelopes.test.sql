-- Manual entry, Claude-only reconciliation and virtual envelopes
-- (migration 20261113000000_manual_entry_and_envelopes.sql).
--
-- Today is 2026-03-10. One checking account with a 1000.00 snapshot on 03-01. Biweekly pay anchored 03-06.
-- Sections:
--   1. add/update/delete_manual_transaction validation (as the signed-in owner, role authenticated)
--   2. guard_transaction_reconciliation (a web session: JWT role = authenticated, direct table writes)
--   3. reconcile/unreconcile are not executable by the API roles
--   4. move_envelope_money limits
--   5. pay_period_forecast cash drops by the active envelope balances
--   6. v_rainy_day_suggestion: a draw of X shrinks gap_to_floor by exactly X
begin;
create extension if not exists pgtap with schema extensions;
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans, public.envelopes cascade;
-- Test-only: new functions are not executable by the API roles by default, which also covers pgTAP.
grant execute on all functions in schema extensions to anon, authenticated;
select plan(65);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-10';

insert into public.accounts (id, name, kind) values ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking');
insert into public.balance_snapshots (account_id, as_of_date, balance) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-01', 1000);
insert into public.income_sources (name, frequency, anchor_date, expected_net, deposit_account_id) values
  ('Job', 'biweekly', '2026-03-06', 2000, 'a0000000-0000-0000-0000-000000000001');
insert into public.bills (id, name, amount, frequency, due_day) values
  ('e0000000-0000-0000-0000-000000000001', 'Water', 100, 'monthly', 20);
select public.ensure_bill_occurrences('2026-03-31');
insert into public.debts (id, name, kind, apr, min_payment, due_day) values
  ('d0000000-0000-0000-0000-000000000001', 'Visa', 'credit_card', 24.99, 35, 12);
insert into public.envelopes (kind, name) values ('rainy_day', 'Rainy-day fund'), ('locked_savings', 'Locked savings');

-- A row Claude imported (entry_source 'import' is the column default)
insert into public.transactions (id, account_id, txn_date, description_raw, merchant, amount, status) values
  ('77000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '2026-03-05', 'KROGER', 'Kroger', -40, 'posted');

-- ============ 1. validation, as the signed-in owner ============
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select throws_ok(
  $$select public.add_manual_transaction(0, '2026-03-09', 'Coffee')$$,
  'P0001', 'Enter an amount', 'add: a zero amount is rejected');
select throws_ok(
  $$select public.add_manual_transaction(-1.005, '2026-03-09', 'Coffee')$$,
  'P0001', 'Amounts have at most two decimal places', 'add: more than two decimals is rejected');
select throws_ok(
  $$select public.add_manual_transaction(-5, '2026-03-11', 'Coffee')$$,
  'P0001', 'The date cannot be in the future', 'add: a future date is rejected');
select throws_ok(
  $$select public.add_manual_transaction(-5, '2026-03-09', 'Paycheck', null, (select id from public.categories where kind = 'income' limit 1))$$,
  'P0001', 'An income category needs money coming in', 'add: an income category with money out is rejected');
select throws_ok(
  $$select public.add_manual_transaction(25, '2026-03-09', 'Water refund', null, null, null, false,
      (select id from public.bill_occurrences limit 1))$$,
  'P0001', 'A bill payment must be money going out', 'add: a bill link with money in is rejected');
select throws_ok(
  $$select public.add_manual_transaction(25, '2026-03-09', 'Visa refund', null, null, null, false, null,
      'd0000000-0000-0000-0000-000000000001')$$,
  'P0001', 'A debt payment must be money going out', 'add: a debt link with money in is rejected');

select lives_ok(
  $$select public.add_manual_transaction(-12.34, '2026-03-09', '  Coffee  ', null, null, 'latte')$$,
  'add: a valid expense (default account) is accepted');
select results_eq(
  $$select amount, status, entry_source, reconciled, cleared, merchant, account_id
      from public.transactions where description_raw = 'Coffee'$$,
  $$values (-12.34::numeric, 'pending'::text, 'manual'::text, false, false, 'Coffee'::text,
            'a0000000-0000-0000-0000-000000000001'::uuid)$$,
  'add: stored pending, manual, unreconciled, trimmed, on the only checking account');
select lives_ok(
  $$select public.add_manual_transaction(300, '2026-03-09', 'Side job', null,
      (select id from public.categories where kind = 'income' limit 1))$$,
  'add: money in with an income category is accepted');
select lives_ok(
  $$select public.add_manual_transaction(-100, '2026-03-09', 'Water bill', null, null, null, false,
      (select id from public.bill_occurrences limit 1), null)$$,
  'add: a bill payment with money out is accepted');
select lives_ok(
  $$select public.add_manual_transaction(-35, '2026-03-09', 'Visa payment', null, null, null, false, null,
      'd0000000-0000-0000-0000-000000000001')$$,
  'add: a debt payment with money out is accepted');

select throws_ok(
  $$select public.update_manual_transaction((select id from public.transactions where merchant = 'Coffee'),
      0, '2026-03-09', 'Coffee')$$,
  'P0001', 'Enter an amount', 'update: a zero amount is rejected');
select throws_ok(
  $$select public.update_manual_transaction((select id from public.transactions where merchant = 'Coffee'),
      -1.005, '2026-03-09', 'Coffee')$$,
  'P0001', 'Amounts have at most two decimal places', 'update: more than two decimals is rejected');
select throws_ok(
  $$select public.update_manual_transaction((select id from public.transactions where merchant = 'Coffee'),
      -5, '2026-03-11', 'Coffee')$$,
  'P0001', 'The date cannot be in the future', 'update: a future date is rejected');
select throws_ok(
  $$select public.update_manual_transaction((select id from public.transactions where merchant = 'Coffee'),
      -5, '2026-03-09', 'Coffee', (select id from public.categories where kind = 'income' limit 1))$$,
  'P0001', 'An income category needs money coming in', 'update: an income category with money out is rejected');
select throws_ok(
  $$select public.update_manual_transaction((select id from public.transactions where merchant = 'Coffee'),
      25, '2026-03-09', 'Coffee', null, null, false, (select id from public.bill_occurrences limit 1))$$,
  'P0001', 'A bill payment must be money going out', 'update: a bill link with money in is rejected');
select throws_ok(
  $$select public.update_manual_transaction((select id from public.transactions where merchant = 'Coffee'),
      25, '2026-03-09', 'Coffee', null, null, false, null, 'd0000000-0000-0000-0000-000000000001')$$,
  'P0001', 'A debt payment must be money going out', 'update: a debt link with money in is rejected');
select throws_ok(
  $$select public.update_manual_transaction('77000000-0000-0000-0000-000000000001', -41, '2026-03-05', 'Kroger')$$,
  'P0001', 'Only manual entries can be edited here', 'update: an imported row cannot be edited');
select lives_ok(
  $$select public.update_manual_transaction((select id from public.transactions where merchant = 'Coffee'),
      -15.50, '2026-03-08', 'Coffee shop', null, 'bigger latte', true)$$,
  'update: a valid edit is accepted');
select results_eq(
  $$select amount, txn_date, merchant, cleared, note from public.transactions where description_raw = 'Coffee shop'$$,
  $$values (-15.50::numeric, '2026-03-08'::date, 'Coffee shop'::text, true, 'bigger latte'::text)$$,
  'update: the row carries the new values');

select throws_ok(
  $$select public.delete_manual_transaction('77000000-0000-0000-0000-000000000001')$$,
  'P0001', 'Only manual entries can be deleted here', 'delete: an imported row cannot be deleted');
select lives_ok(
  $$select public.delete_manual_transaction((select id from public.transactions where merchant = 'Coffee shop'))$$,
  'delete: a manual row can be deleted');
select is((select count(*)::int from public.transactions where merchant = 'Coffee shop'), 0,
          'delete: the row is gone');

-- ============ 2. the reconciliation guard ============
-- A web session is a JWT with role = authenticated. Test as the table owner (so privileges do not mask
-- the trigger) with that claim set; the five functions above run under the same claim.
reset role;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select throws_ok(
  $$insert into public.transactions (account_id, txn_date, description_raw, amount, entry_source, reconciled)
    values ('a0000000-0000-0000-0000-000000000001', '2026-03-09', 'SNEAKY', -1, 'manual', true)$$,
  '42501', 'The web app can only add unreconciled manual entries', 'guard: a web session cannot insert a reconciled row');
select throws_ok(
  $$insert into public.transactions (account_id, txn_date, description_raw, amount, entry_source)
    values ('a0000000-0000-0000-0000-000000000001', '2026-03-09', 'SNEAKY', -1, 'import')$$,
  '42501', 'The web app can only add unreconciled manual entries', 'guard: a web session cannot insert an import row');
select throws_ok(
  $$update public.transactions set reconciled = true where merchant = 'Water bill'$$,
  '42501', 'Only Claude can change reconciliation', 'guard: a web session cannot set reconciled');
select throws_ok(
  $$update public.transactions set reconciled_at = now() where merchant = 'Water bill'$$,
  '42501', 'Only Claude can change reconciliation', 'guard: a web session cannot set reconciled_at');
select throws_ok(
  $$update public.transactions set entry_source = 'import' where merchant = 'Water bill'$$,
  '42501', 'entry_source cannot be changed', 'guard: a web session cannot change entry_source');
select throws_ok(
  $$delete from public.transactions where id = '77000000-0000-0000-0000-000000000001'$$,
  '42501', 'Only manual entries can be deleted from the web app', 'guard: a web session cannot delete an imported row');

-- The guard treats an uncleared reconciled row as locked for every edit, so mark the Water bill row cleared
-- first (reconcile_transactions only forces cleared for rows that are already posted).
select lives_ok(
  $$select public.set_transaction_cleared((select id from public.transactions where merchant = 'Water bill'), true)$$,
  'the owner marks the Water bill row cleared before Claude reconciles it');

-- Claude (no web JWT) reconciles the manual Water bill row and the imported Kroger row
set local request.jwt.claims = '';
select is(public.reconcile_transactions(array[
            (select id from public.transactions where merchant = 'Water bill'),
            '77000000-0000-0000-0000-000000000001'::uuid]),
          2, 'Claude can reconcile rows (no web session)');
select results_eq(
  $$select reconciled, reconciled_at is not null from public.transactions where merchant = 'Water bill'$$,
  $$values (true, true)$$, 'reconcile sets reconciled and reconciled_at');

set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select throws_ok(
  $$update public.transactions set amount = -99 where merchant = 'Water bill'$$,
  '42501', 'A reconciled transaction can no longer be changed', 'guard: a web session cannot edit the amount of a reconciled row');
select throws_ok(
  $$update public.transactions set txn_date = '2026-03-01' where merchant = 'Water bill'$$,
  '42501', 'A reconciled transaction can no longer be changed', 'guard: a web session cannot edit the date of a reconciled row');
select throws_ok(
  $$update public.transactions set status = 'posted' where merchant = 'Water bill'$$,
  '42501', 'A reconciled transaction can no longer be changed', 'guard: a web session cannot edit the status of a reconciled row');
select throws_ok(
  $$delete from public.transactions where merchant = 'Water bill'$$,
  '42501', 'A reconciled transaction cannot be deleted', 'guard: a web session cannot delete a reconciled row');
select lives_ok(
  $$update public.transactions set note = 'checked', category_id = null where merchant = 'Water bill'$$,
  'guard: a web session can still annotate a reconciled row');
select throws_ok(
  $$select public.update_manual_transaction((select id from public.transactions where merchant = 'Water bill'),
      -100, '2026-03-09', 'Water bill')$$,
  'P0001', 'Claude already reconciled this transaction, so it is locked', 'update_manual_transaction refuses a reconciled row');
select throws_ok(
  $$select public.delete_manual_transaction((select id from public.transactions where merchant = 'Water bill'))$$,
  'P0001', 'Claude already reconciled this transaction, so it is locked', 'delete_manual_transaction refuses a reconciled row');
select throws_ok(
  $$select public.set_transaction_cleared((select id from public.transactions where merchant = 'Water bill'), false)$$,
  'P0001', 'A reconciled transaction stays cleared', 'set_transaction_cleared cannot un-clear a reconciled row');
select lives_ok(
  $$select public.set_transaction_cleared((select id from public.transactions where merchant = 'Visa payment'), true)$$,
  'set_transaction_cleared works on an unreconciled row');

set local request.jwt.claims = '';
select is(public.unreconcile_transactions(array[(select id from public.transactions where merchant = 'Water bill')]),
          1, 'Claude can unreconcile a row (no web session)');

-- ============ 3. reconcile/unreconcile are Claude-only ============
select ok(not has_function_privilege('authenticated', 'public.reconcile_transactions(uuid[])', 'execute'),
          'authenticated cannot execute reconcile_transactions');
select ok(not has_function_privilege('authenticated', 'public.unreconcile_transactions(uuid[])', 'execute'),
          'authenticated cannot execute unreconcile_transactions');
select ok(not has_function_privilege('anon', 'public.reconcile_transactions(uuid[])', 'execute')
      and not has_function_privilege('anon', 'public.unreconcile_transactions(uuid[])', 'execute'),
          'anon cannot execute reconcile or unreconcile');
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select throws_ok(
  $$select public.reconcile_transactions(array['77000000-0000-0000-0000-000000000001'::uuid])$$,
  '42501', null, 'calling reconcile_transactions as authenticated is denied');
select throws_ok(
  $$select public.unreconcile_transactions(array['77000000-0000-0000-0000-000000000001'::uuid])$$,
  '42501', null, 'calling unreconcile_transactions as authenticated is denied');
reset role;
select ok(has_function_privilege('authenticated', 'public.add_manual_transaction(numeric,date,text,uuid,uuid,text,boolean,uuid,uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.move_envelope_money(uuid,numeric,text,date)', 'execute')
      and not has_function_privilege('anon', 'public.add_manual_transaction(numeric,date,text,uuid,uuid,text,boolean,uuid,uuid)', 'execute')
      and not has_function_privilege('anon', 'public.move_envelope_money(uuid,numeric,text,date)', 'execute'),
          'the web writers are granted to authenticated and not to anon');

-- ============ 4. envelope limits ============
-- Forecast baseline before any envelope money exists (taken now, before any envelope moves).
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
create temp table base as
  select f.starting_cash, f.binding_balance from public.pay_period_forecast(2, 1) f where f.period_index = 1;

select throws_ok(
  format($f$select public.move_envelope_money(%L, -10)$f$, (select id from public.envelopes where kind = 'rainy_day')),
  'P0001', 'Only 0 is in Rainy-day fund', 'moving out of an empty envelope is rejected');
select throws_like(
  format($f$select public.move_envelope_money(%L, %s)$f$, (select id from public.envelopes where kind = 'rainy_day'),
         (select sum(ab.estimated_balance) + 0.01 from public.v_account_balances ab
           where ab.is_active and ab.kind in ('checking', 'savings', 'cash'))),
  'Envelopes cannot hold more than the cash you have%', 'putting in more than the real cash is rejected');
select is(public.move_envelope_money((select id from public.envelopes where kind = 'rainy_day'), 400, 'start'),
          400::numeric, 'a valid move returns the new envelope balance');
select throws_like(
  format($f$select public.move_envelope_money(%L, %s)$f$, (select id from public.envelopes where kind = 'locked_savings'),
         (select sum(ab.estimated_balance) - 400 + 0.01 from public.v_account_balances ab
           where ab.is_active and ab.kind in ('checking', 'savings', 'cash'))),
  'Envelopes cannot hold more than the cash you have%', 'the cap counts every active envelope together');
select throws_ok(
  format($f$select public.move_envelope_money(%L, -400.01)$f$, (select id from public.envelopes where kind = 'rainy_day')),
  'P0001', 'Only 400.00 is in Rainy-day fund', 'overdrawing by a cent is rejected');
select throws_ok(
  format($f$select public.move_envelope_money(%L, 1.001)$f$, (select id from public.envelopes where kind = 'rainy_day')),
  'P0001', 'Amounts have at most two decimal places', 'envelope moves also reject more than two decimals');
select lives_ok(
  format($f$select public.move_envelope_money(%L, 100, 'locked')$f$, (select id from public.envelopes where kind = 'locked_savings')),
  'a move into locked savings is accepted');

-- ============ 5. forecast cash drops by the active envelope balances ============
select is((select f.starting_cash from public.pay_period_forecast(2, 1) f where f.period_index = 1),
          (select b.starting_cash - 500 from base b),
          'forecast starting_cash drops by rainy-day (400) plus locked savings (100)');
update public.envelopes set is_active = false where kind = 'locked_savings';
select is((select f.starting_cash from public.pay_period_forecast(2, 1) f where f.period_index = 1),
          (select b.starting_cash - 400 from base b),
          'an inactive envelope no longer reduces forecast cash');
select throws_ok(
  format($f$select public.move_envelope_money(%L, 5)$f$, (select id from public.envelopes where kind = 'locked_savings')),
  'P0001', 'Unknown or inactive envelope', 'an inactive envelope takes no moves');
update public.envelopes set is_active = true where kind = 'locked_savings';
select is((select balance from public.v_envelopes where kind = 'locked_savings'), 100.00::numeric,
          'v_envelopes shows the locked savings balance');

-- ============ 6. rainy-day suggestion ============
-- Raise the floor far above any projected balance so the current period is short.
update public.app_settings set low_balance_threshold = 5000 where id;
create temp table before_draw as
  select s.gap_to_floor, s.binding_balance, s.rainy_balance, s.suggested_draw, s.remaining_gap
    from public.v_rainy_day_suggestion s;

select ok((select gap_to_floor > 150 from before_draw), 'the current period is short of the floor');
select is((select suggested_draw from before_draw), (select least(rainy_balance, gap_to_floor) from before_draw),
          'suggested_draw is the smaller of the rainy-day balance and the gap');
select is((select remaining_gap from before_draw), (select gap_to_floor - suggested_draw from before_draw),
          'remaining_gap is what the draw leaves uncovered');

-- Drawing X out of the rainy-day envelope returns X to spendable cash, so the gap shrinks by exactly X.
select lives_ok(
  format($f$select public.move_envelope_money(%L, -150, 'draw')$f$, (select id from public.envelopes where kind = 'rainy_day')),
  'draw 150 from the rainy-day fund');
select is((select gap_to_floor from public.v_rainy_day_suggestion),
          (select gap_to_floor - 150 from before_draw),
          'a draw of 150 reduces gap_to_floor by exactly 150');
select is((select rainy_balance from public.v_rainy_day_suggestion), (select rainy_balance - 150 from before_draw),
          'the rainy-day balance is down by the draw');

select * from finish();
rollback;
