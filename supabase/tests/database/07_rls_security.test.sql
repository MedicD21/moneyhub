-- Phase 1: as an authenticated user, insert/update/delete fail on every table,
-- select returns only owned rows; anon gets nothing; writer functions are not
-- callable from the API roles.
begin;
create extension if not exists pgtap with schema extensions;
select plan(68);

-- Owner A (the app owner) and an unrelated user B
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'owner@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'other@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-10';

insert into public.accounts (id, owner_id, name, kind) values
  ('a0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'A Checking', 'checking'),
  ('a0000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'B Checking', 'checking');
insert into public.transactions (owner_id, account_id, txn_date, description_raw, amount, needs_review) values
  ('11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001', '2026-03-02', 'A TXN', -10, true),
  ('22222222-2222-2222-2222-222222222222', 'a0000000-0000-0000-0000-000000000002', '2026-03-02', 'B TXN', -99, true);
insert into public.balance_snapshots (owner_id, account_id, as_of_date, balance) values
  ('11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001', '2026-03-01', 100),
  ('22222222-2222-2222-2222-222222222222', 'a0000000-0000-0000-0000-000000000002', '2026-03-01', 5000);

-- RLS is on for every table, and every table has exactly the one select policy
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  0, 'RLS is enabled on every table in public');
select is(
  (select count(*)::int from pg_policies where schemaname = 'public' and cmd <> 'SELECT'),
  0, 'no insert/update/delete/all policies exist');
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'v'
      and not coalesce((select bool_or(o = 'security_invoker=true') from unnest(c.reloptions) o), false)),
  0, 'every view is security_invoker');

-- ============ authenticated as owner A ============
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select results_eq($$select name from public.accounts$$, $$values ('A Checking'::text)$$,
                  'A sees only own accounts');
select results_eq($$select description_raw from public.v_transactions$$, $$values ('A TXN'::text)$$,
                  'views apply RLS (v_transactions)');
select is((select review_queue_count::int from public.v_dashboard), 1, 'v_dashboard counts only own review items');
select is((select total_cash from public.v_dashboard), 90.00::numeric, 'v_dashboard total_cash uses only own accounts');
select is((select count(*)::int from public.categories), 18, 'A sees own seeded categories');

-- Insert / update / delete / truncate fail on every table
select throws_ok(format('insert into public.%I default values', t), '42501', null,
                 format('authenticated cannot INSERT into %s', t))
from unnest(array['app_settings','accounts','import_batches','categories','transactions','balance_snapshots',
                  'merchant_rules','income_sources','bills','bill_occurrences','debts','debt_balances',
                  'set_asides','debt_plans']) t;
select throws_ok(format('update public.%I set owner_id = owner_id', t), '42501', null,
                 format('authenticated cannot UPDATE %s', t))
from unnest(array['app_settings','accounts','import_batches','categories','transactions','balance_snapshots',
                  'merchant_rules','income_sources','bills','bill_occurrences','debts','debt_balances',
                  'set_asides','debt_plans']) t;
select throws_ok(format('delete from public.%I', t), '42501', null,
                 format('authenticated cannot DELETE from %s', t))
from unnest(array['app_settings','accounts','import_batches','categories','transactions','balance_snapshots',
                  'merchant_rules','income_sources','bills','bill_occurrences','debts','debt_balances',
                  'set_asides','debt_plans']) t;
select throws_ok(format('truncate public.%I cascade', t), '42501', null,
                 format('authenticated cannot TRUNCATE %s', t))
from unnest(array['accounts','transactions','balance_snapshots','bills']) t;

-- Writer functions are not executable
select throws_ok($$select public.ensure_bill_occurrences()$$, '42501', null,
                 'authenticated cannot run ensure_bill_occurrences');
select throws_ok($$select public.commit_screenshot_import('a0000000-0000-0000-0000-000000000001', '[]')$$,
                 '42501', null, 'authenticated cannot run commit_screenshot_import');
select throws_ok($$select public.mark_bill_paid(gen_random_uuid(), gen_random_uuid())$$, '42501', null,
                 'authenticated cannot run mark_bill_paid');
select throws_ok($$select public.bootstrap_owner('x@test.local')$$, '42501', null,
                 'authenticated cannot run bootstrap_owner');
-- Read functions are
select lives_ok($$select * from public.paycheck_plan()$$, 'authenticated can read paycheck_plan()');
select lives_ok($$select * from public.v_pay_periods$$,   'authenticated can read v_pay_periods');

-- ============ authenticated as user B ============
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select results_eq($$select name from public.accounts$$, $$values ('B Checking'::text)$$,
                  'B sees only own accounts');
select is((select count(*)::int from public.app_settings), 0, 'B cannot see the owner settings row');
select is((select count(*)::int from public.categories), 0, 'B cannot see the owner categories');

-- ============ second layer: even WITH table grants, RLS blocks writes ============
reset role;
grant insert, update, delete on public.accounts to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select throws_ok(
  $$insert into public.accounts (name, kind) values ('Sneaky', 'cash')$$,
  '42501', null, 'with a grant, RLS still rejects INSERT (no insert policy)');
update public.accounts set name = 'Renamed';
delete from public.accounts;
reset role;
select results_eq($$select name from public.accounts order by name$$,
                  $$values ('A Checking'::text), ('B Checking')$$,
                  'with a grant, RLS makes UPDATE and DELETE affect 0 rows');

-- ============ anon ============
set local role anon;
select throws_ok($$select * from public.accounts$$, '42501', null, 'anon cannot read tables');
select throws_ok($$select * from public.v_dashboard$$, '42501', null, 'anon cannot read views');
select throws_ok($$select * from public.paycheck_plan()$$, '42501', null, 'anon cannot run functions');
reset role;

select * from finish();
rollback;
