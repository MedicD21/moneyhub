-- create_set_aside / update_set_aside (migration 20261113050000_set_aside_writes.sql).
--
-- Today 2026-03-10. One checking account with a 1000.00 snapshot on 03-01. Biweekly pay anchored 03-06.
-- Sections: 1. create validation  2. create + derived balance  3. update, pause, resume
--           4. privileges and the owner check (web owner, other user's category, anon, direct session)
begin;
create extension if not exists pgtap with schema extensions;
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans, public.envelopes cascade;
grant execute on all functions in schema extensions to anon, authenticated;
select plan(35);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'owner@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'someone@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-10';

insert into public.accounts (id, name, kind) values ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking');
insert into public.balance_snapshots (account_id, as_of_date, balance) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-01', 1000);
insert into public.income_sources (name, frequency, anchor_date, expected_net, deposit_account_id) values
  ('Job', 'biweekly', '2026-03-06', 2000, 'a0000000-0000-0000-0000-000000000001');
-- A category owned by someone else (only possible by writing as the table owner).
insert into public.categories (id, owner_id, name, kind) values
  ('c0000000-0000-0000-0000-00000000beef', '22222222-2222-2222-2222-222222222222', 'Not yours', 'expense');

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- ============ 1. create validation ============
select throws_ok($$select public.create_set_aside('  ', 50)$$, 'P0001', 'Enter a name', 'create: a blank name is rejected');
select throws_ok($$select public.create_set_aside(repeat('x', 61), 50)$$, 'P0001', 'Names are at most 60 characters',
                 'create: 61 characters is rejected');
select throws_ok($$select public.create_set_aside('Car', null)$$, 'P0001', 'Enter an amount per paycheck (0 is allowed)',
                 'create: a missing per-paycheck amount is rejected');
select throws_ok($$select public.create_set_aside('Car', -1)$$, 'P0001', 'The amount per paycheck cannot be negative',
                 'create: a negative per-paycheck amount is rejected');
select throws_ok($$select public.create_set_aside('Car', 10.005)$$, 'P0001', 'Amounts have at most two decimal places',
                 'create: more than two decimals is rejected');
select throws_ok($$select public.create_set_aside('Car', 50, -5)$$, 'P0001', 'The cap cannot be negative',
                 'create: a negative cap is rejected');
select throws_ok($$select public.create_set_aside('Car', 50, null, '2028-01-01')$$, 'P0001',
                 'Pick a start date within a year of today', 'create: a far-off start date is rejected');
select throws_ok($$select public.create_set_aside('Car', 50, null, null, 0, 'c0000000-0000-0000-0000-00000000beef')$$,
                 'P0001', 'Unknown category', 'create: another owner''s category is rejected');
select throws_ok($$select public.create_set_aside('Car', 50, null, null, 0, '00000000-0000-0000-0000-000000000000')$$,
                 'P0001', 'Unknown category', 'create: a missing category is rejected');

-- ============ 2. create + derived balance ============
select lives_ok(
  $$select public.create_set_aside('  Car & fuel  ', 50, 300, '2026-03-06', 20,
      (select id from public.categories where name = 'Gas'))$$,
  'create: a valid set-aside is accepted');
select results_eq(
  $$select name, per_paycheck, cap, start_date, opening_balance, category_name, is_active
      from public.v_set_asides where name = 'Car & fuel'$$,
  $$values ('Car & fuel'::text, 50.00::numeric, 300.00::numeric, '2026-03-06'::date, 20.00::numeric, 'Gas'::text, true)$$,
  'create: v_set_asides shows the stored settings, trimmed name and category');
select is((select balance from public.v_set_asides where name = 'Car & fuel'), 70.00::numeric,
          'the balance comes from the database ledger (20 opening + 50 on the 03-06 payday)');
select lives_ok($$select public.create_set_aside('Gifts', 0)$$, 'create: 0 per paycheck is allowed, start defaults to today');
select is((select start_date from public.v_set_asides where name = 'Gifts'), '2026-03-10'::date, 'create: start_date defaults to today');
select throws_ok($$select public.create_set_aside('car & FUEL', 10)$$, 'P0001', 'You already have a set-aside called car & FUEL',
                 'create: a duplicate active name (any case) is rejected');
select throws_ok($$select public.create_set_aside('Gas money', 10, null, null, 0, (select id from public.categories where name = 'Gas'))$$,
                 'P0001', 'That category already draws from the set-aside Car & fuel',
                 'create: a category can feed only one active set-aside');

-- ============ 3. update, pause, resume ============
select throws_ok(
  $$select public.update_set_aside('00000000-0000-0000-0000-000000000000', 'X', 1, null, '2026-03-10', 0, null, true)$$,
  'P0001', 'Unknown set-aside', 'update: an unknown id is rejected');
select throws_ok(
  format($f$select public.update_set_aside(%L, 'Car & fuel', 50, 300, '2026-03-06', 20, null, null)$f$,
         (select id from public.set_asides where name = 'Car & fuel')),
  'P0001', 'Choose active or paused', 'update: is_active must be given');
select throws_ok(
  format($f$select public.update_set_aside(%L, 'Gifts', 50, 300, '2026-03-06', 20, null, true)$f$,
         (select id from public.set_asides where name = 'Car & fuel')),
  'P0001', 'You already have a set-aside called Gifts', 'update: renaming onto another active name is rejected');
select lives_ok(
  format($f$select public.update_set_aside(%L, 'Car', 60, null, '2026-03-06', 20, (select id from public.categories where name = 'Gas'), true)$f$,
         (select id from public.set_asides where name = 'Car & fuel')),
  'update: name, amount and cap can change');
select results_eq(
  $$select name, per_paycheck, cap, balance from public.v_set_asides where name = 'Car'$$,
  $$values ('Car'::text, 60.00::numeric, null::numeric, 80.00::numeric)$$,
  'update: the balance is recomputed by the database from the new settings');

select is((select set_asides_total from public.paycheck_plan()), 60.00::numeric, 'the active set-aside feeds paycheck_plan');
select lives_ok(
  format($f$select public.update_set_aside(%L, 'Car', 60, null, '2026-03-06', 20, (select id from public.categories where name = 'Gas'), false)$f$,
         (select id from public.set_asides where name = 'Car')),
  'update: a set-aside can be paused');
select is((select set_asides_total from public.paycheck_plan()), 0.00::numeric, 'a paused set-aside takes nothing from the paycheck');
select is((select count(*)::int from public.set_asides), 2, 'pausing keeps the row (no delete)');
select lives_ok($$select public.create_set_aside('Car', 25, null, null, 0, (select id from public.categories where name = 'Gas'))$$,
                'a paused set-aside frees its name and category');
select throws_ok(
  format($f$select public.update_set_aside(%L, 'Car', 60, null, '2026-03-06', 20, null, true)$f$,
         (select id from public.set_asides where name = 'Car' and not is_active)),
  'P0001', 'You already have a set-aside called Car', 'resuming onto an active name is rejected');

-- An old set-aside (start date over a year ago) can still be paused with its stored date, but not moved to
-- another out-of-range date.
reset role;
update public.set_asides set start_date = '2024-01-05' where name = 'Gifts';
set local role authenticated;
select lives_ok(
  format($f$select public.update_set_aside(%L, 'Gifts', 0, null, '2024-01-05', 0, null, false)$f$,
         (select id from public.set_asides where name = 'Gifts')),
  'update: an old set-aside keeps its stored start date and can be paused');
select throws_ok(
  format($f$select public.update_set_aside(%L, 'Gifts', 0, null, '2024-01-06', 0, null, false)$f$,
         (select id from public.set_asides where name = 'Gifts')),
  'P0001', 'Pick a start date within a year of today', 'update: a new out-of-range start date is still rejected');

-- ============ 4. privileges and the owner check ============
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select throws_ok($$select public.create_set_aside('Mine', 5)$$, '42501', 'Not signed in as the Money Hub owner',
                 'create: a signed-in non-owner is rejected');
select throws_ok(
  format($f$select public.update_set_aside(%L, 'Gifts', 0, null, '2026-03-10', 0, null, false)$f$,
         (select id from public.set_asides where name = 'Gifts')),
  '42501', 'Not signed in as the Money Hub owner', 'update: a signed-in non-owner is rejected');

reset role;
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok($$select public.create_set_aside('Anon', 5)$$, '42501', null, 'anon cannot call create_set_aside');
reset role;

select ok(has_function_privilege('authenticated', 'public.create_set_aside(text,numeric,numeric,date,numeric,uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.update_set_aside(uuid,text,numeric,numeric,date,numeric,uuid,boolean)', 'execute')
      and not has_function_privilege('anon', 'public.create_set_aside(text,numeric,numeric,date,numeric,uuid)', 'execute')
      and not has_function_privilege('anon', 'public.update_set_aside(uuid,text,numeric,numeric,date,numeric,uuid,boolean)', 'execute'),
          'the web role can call both set-aside writers; anon cannot');
select ok(not has_function_privilege('authenticated', 'public.set_aside_input_check(uuid,uuid,text,numeric,numeric,date,numeric,uuid,boolean)', 'execute'),
          'the internal validator is not callable by the web role');

set local request.jwt.claims = '';
select lives_ok($$select public.create_set_aside('From chat', 10)$$, 'a direct session with no JWT can create a set-aside');

select * from finish();
rollback;
