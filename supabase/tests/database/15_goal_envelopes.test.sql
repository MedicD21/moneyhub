-- Goal envelopes (migration 20261113040000_goal_envelopes.sql).
--
-- Today 2026-03-10. One checking account with a 1000.00 snapshot on 03-01. Biweekly pay anchored 03-06.
-- Sections: 1. table rules  2. create_envelope  3. update_envelope  4. forecast and rainy-day suggestion
--           5. privileges and the owner check (web owner, other user, anon, direct session)
begin;
create extension if not exists pgtap with schema extensions;
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans, public.envelopes cascade;
grant execute on all functions in schema extensions to anon, authenticated;
select plan(37);

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
insert into public.envelopes (kind, name) values ('rainy_day', 'Rainy-day fund'), ('locked_savings', 'Locked savings');

-- ============ 1. table rules ============
select throws_ok(
  $$insert into public.envelopes (kind, name) values ('rainy_day', 'Second rainy')$$,
  '23505', null, 'a second rainy-day fund is rejected');
select throws_ok(
  $$insert into public.envelopes (kind, name) values ('locked_savings', 'Second locked')$$,
  '23505', null, 'a second locked savings is rejected');
select throws_ok(
  $$insert into public.envelopes (kind, name) values ('cookie_jar', 'Jar')$$,
  '23514', null, 'an unknown kind is rejected');
select throws_ok(
  $$insert into public.envelopes (kind, name) values ('goal', '  padded  ')$$,
  '23514', null, 'an untrimmed name is rejected by the table');

-- ============ 2. create_envelope, as the signed-in owner ============
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select throws_ok($$select public.create_envelope('   ')$$, 'P0001', 'Enter a name', 'create: a blank name is rejected');
select throws_ok($$select public.create_envelope(null)$$, 'P0001', 'Enter a name', 'create: a null name is rejected');
select throws_ok($$select public.create_envelope(repeat('x', 61))$$, 'P0001', 'Names are at most 60 characters',
                 'create: 61 characters is rejected');
select lives_ok($$select public.create_envelope(repeat('y', 60))$$, 'create: 60 characters is accepted');
select throws_ok($$select public.create_envelope('rainy-DAY fund')$$, 'P0001',
                 'You already have an envelope called rainy-DAY fund',
                 'create: a name matching an active envelope (any case) is rejected');
select lives_ok($$select public.create_envelope('  Vacation  ')$$, 'create: a goal envelope is created');
select results_eq(
  $$select kind, name, balance, is_active from public.v_envelopes where name = 'Vacation'$$,
  $$values ('goal'::text, 'Vacation'::text, 0.00::numeric, true)$$,
  'create: stored trimmed, kind goal, balance 0, active, visible in v_envelopes');
select lives_ok($$select public.create_envelope('New tires')$$, 'create: more than one goal envelope is allowed');
select throws_ok($$select public.create_envelope('vacation')$$, 'P0001', 'You already have an envelope called vacation',
                 'create: a duplicate goal name is rejected');

-- ============ 3. update_envelope ============
select throws_ok(
  format($f$select public.update_envelope(%L, 'Renamed', true)$f$, (select id from public.envelopes where kind = 'rainy_day')),
  'P0001', 'The rainy-day fund and locked savings cannot be renamed or archived', 'update: the rainy-day fund is fixed');
select throws_ok(
  format($f$select public.update_envelope(%L, 'Locked savings', false)$f$, (select id from public.envelopes where kind = 'locked_savings')),
  'P0001', 'The rainy-day fund and locked savings cannot be renamed or archived', 'update: locked savings cannot be archived');
select throws_ok(
  $$select public.update_envelope('00000000-0000-0000-0000-000000000000', 'X', true)$$,
  'P0001', 'Unknown envelope', 'update: an unknown id is rejected');
select throws_ok(
  format($f$select public.update_envelope(%L, 'New tires', true)$f$, (select id from public.envelopes where name = 'Vacation')),
  'P0001', 'You already have an envelope called New tires', 'update: renaming onto another active name is rejected');
select lives_ok(
  format($f$select public.update_envelope(%L, 'Beach trip', true)$f$, (select id from public.envelopes where name = 'Vacation')),
  'update: a goal envelope can be renamed');

select is(public.move_envelope_money((select id from public.envelopes where name = 'Beach trip'), 100, 'saving'),
          100::numeric, 'move_envelope_money works on a goal envelope');
select throws_ok(
  format($f$select public.update_envelope(%L, 'Beach trip', false)$f$, (select id from public.envelopes where name = 'Beach trip')),
  'P0001', 'Move the 100.00 out of Beach trip before archiving it', 'update: archiving with a non-zero balance is blocked');

-- ============ 4. forecast and the rainy-day suggestion ============
select is((select f.starting_cash from public.pay_period_forecast(2, 1) f where f.period_index = 1), 900.00::numeric,
          'a goal envelope balance (100) comes off forecast starting cash, like locked savings');
select throws_like(
  format($f$select public.move_envelope_money(%L, 900.01)$f$, (select id from public.envelopes where name = 'New tires')),
  'Envelopes cannot hold more than the cash you have%', 'the cash cap counts goal envelopes too');

reset role;
update public.app_settings set low_balance_threshold = 50000 where id;
set local role authenticated;
select results_eq(
  $$select envelope_id, rainy_balance from public.v_rainy_day_suggestion$$,
  $$select id, 0.00::numeric from public.envelopes where kind = 'rainy_day'$$,
  'v_rainy_day_suggestion reads only the rainy-day fund, never a goal envelope');
select is((select suggested_draw from public.v_rainy_day_suggestion), 0.00::numeric,
          'the goal envelope money is never suggested as a draw');

select is(public.move_envelope_money((select id from public.envelopes where name = 'Beach trip'), -100, 'spent'),
          0::numeric, 'moving the goal money back out leaves 0');
select lives_ok(
  format($f$select public.update_envelope(%L, 'Beach trip', false)$f$, (select id from public.envelopes where name = 'Beach trip')),
  'update: a goal envelope at 0 can be archived');
select is((select is_active from public.v_envelopes where name = 'Beach trip'), false, 'archived envelopes stay in v_envelopes');
select throws_ok(
  format($f$select public.move_envelope_money(%L, 5)$f$, (select id from public.envelopes where name = 'Beach trip')),
  'P0001', 'Unknown or inactive envelope', 'an archived envelope takes no moves');
select lives_ok($$select public.create_envelope('Beach trip')$$, 'an archived name can be reused');
select throws_ok(
  format($f$select public.update_envelope(%L, 'Beach trip', true)$f$,
         (select id from public.envelopes where name = 'Beach trip' and not is_active)),
  'P0001', 'You already have an envelope called Beach trip', 'restoring onto an active name is rejected');

-- ============ 5. privileges and the owner check ============
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select throws_ok($$select public.create_envelope('Not mine')$$, '42501', 'Not signed in as the Money Hub owner',
                 'create: a signed-in non-owner is rejected');
select throws_ok(
  format($f$select public.update_envelope(%L, 'Hijack', true)$f$, (select id from public.envelopes where name = 'New tires')),
  '42501', 'Not signed in as the Money Hub owner', 'update: a signed-in non-owner is rejected');

reset role;
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok($$select public.create_envelope('Anon')$$, '42501', null, 'anon cannot call create_envelope');
reset role;

select ok(has_function_privilege('authenticated', 'public.create_envelope(text)', 'execute')
      and has_function_privilege('authenticated', 'public.update_envelope(uuid,text,boolean)', 'execute'),
          'the web role can call create_envelope and update_envelope');
select ok(not has_function_privilege('anon', 'public.create_envelope(text)', 'execute')
      and not has_function_privilege('anon', 'public.update_envelope(uuid,text,boolean)', 'execute')
      and not has_function_privilege('authenticated', 'public.app_owner_for_write()', 'execute')
      and not has_function_privilege('anon', 'public.app_owner_for_write()', 'execute'),
          'anon cannot call them, and nobody on the API can call app_owner_for_write directly');

-- A direct database session with no JWT (the Claude chat's connector) acts for the owner.
set local request.jwt.claims = '';
select lives_ok($$select public.create_envelope('From chat')$$, 'a direct session with no JWT can create an envelope');
select is((select owner_id from public.envelopes where name = 'From chat'), '11111111-1111-1111-1111-111111111111'::uuid,
          'and it belongs to the configured owner');

select * from finish();
rollback;
