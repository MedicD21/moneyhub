-- delete_set_aside (migration 20261127190000_delete_set_aside.sql).
-- Only a paused set-aside can be deleted. Unreconciled tagged transactions keep all their data except the link;
-- a set-aside with reconciled transactions tagged to it cannot be deleted (the reconciliation guard is not weakened).
begin;
create extension if not exists pgtap with schema extensions;
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans, public.envelopes cascade;
grant execute on all functions in schema extensions to anon, authenticated;
select plan(10);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-10';

insert into public.accounts (id, name, kind) values ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking');
insert into public.balance_snapshots (account_id, as_of_date, balance) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-01', 1000);
insert into public.income_sources (name, frequency, anchor_date, expected_net, deposit_account_id) values
  ('Job', 'biweekly', '2026-03-06', 2000, 'a0000000-0000-0000-0000-000000000001');

-- set-asides and a bank-imported, reconciled transaction tagged to the first one, written as the table owner
-- (like an import) before switching to the signed-in web role
insert into public.set_asides (owner_id, name, per_paycheck, start_date, opening_balance, is_active) values
  ('11111111-1111-1111-1111-111111111111', 'Car & fuel', 50, '2026-03-01', 0, true),
  ('11111111-1111-1111-1111-111111111111', 'Trip',       25, '2026-03-01', 0, true);
insert into public.transactions (id, account_id, txn_date, description_raw, amount, set_aside_id, entry_source, status)
select 'f0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', '2026-03-06', 'Hotel deposit', -60.00,
       (select id from public.set_asides where name = 'Trip'), 'manual', 'pending';
insert into public.transactions (id, account_id, txn_date, description_raw, amount, set_aside_id, entry_source, reconciled, reconciled_at)
select 'f0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '2026-03-05', 'SHELL OIL', -40.00,
       (select id from public.set_asides where name = 'Car & fuel'), 'import', true, now();

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select throws_ok($$select public.delete_set_aside((select id from public.set_asides where name = 'Car & fuel'))$$,
                 'P0001', 'Pause the set-aside before deleting it', 'an active set-aside cannot be deleted');
select throws_ok($$select public.delete_set_aside('99999999-9999-9999-9999-999999999999')$$,
                 'P0001', 'Unknown set-aside', 'an unknown id is rejected');

select public.update_set_aside(sa.id, sa.name, sa.per_paycheck, sa.cap, sa.start_date, sa.opening_balance, sa.category_id, false)
  from public.set_asides sa where sa.name in ('Car & fuel', 'Trip');

select throws_ok($$select public.delete_set_aside((select id from public.set_asides where name = 'Car & fuel'))$$,
                 'P0001', 'Bank-reconciled transactions are tagged to this set-aside, so it can only be paused',
                 'a set-aside with reconciled transactions tagged to it cannot be deleted');
select lives_ok($$select public.delete_set_aside((select id from public.set_asides where name = 'Trip'))$$,
                'a paused set-aside can be deleted');
select is((select count(*)::int from public.set_asides where name = 'Trip'), 0, 'the set-aside is gone');
select is((select count(*)::int from public.set_asides where name = 'Car & fuel'), 1, 'the blocked set-aside is still there');
select results_eq(
  $$select amount, status, set_aside_id is null from public.transactions where id = 'f0000000-0000-0000-0000-000000000002'$$,
  $$values (-60.00::numeric, 'pending', true)$$,
  'the tagged manual transaction keeps its amount and status; only the link is cleared');

reset role;
select ok(not has_function_privilege('anon', 'public.delete_set_aside(uuid)', 'execute'), 'anon cannot call delete_set_aside');
select ok(has_function_privilege('authenticated', 'public.delete_set_aside(uuid)', 'execute'), 'authenticated can call delete_set_aside');
set local role anon;
select throws_ok($$select public.delete_set_aside('99999999-9999-9999-9999-999999999999')$$, '42501', null, 'anon is denied');
reset role;

select * from finish();
rollback;
