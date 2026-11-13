-- move_envelope_money counts set-aside balances (migration 20261113030000_envelope_cap_counts_set_aside_reserves.sql).
--
-- Today 2026-03-10. One checking account with a 1000.00 snapshot on 03-01 and no later transactions.
-- Set-aside "Car" holds 600 (opening balance, no contributions), so 400 is free for envelopes.
-- Set-aside "Overspent" is at -200: a negative balance must not free up room.
begin;
create extension if not exists pgtap with schema extensions;
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans, public.envelopes cascade;
grant execute on all functions in schema extensions to anon, authenticated;
select plan(11);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-10';

insert into public.accounts (id, name, kind) values ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking');
insert into public.balance_snapshots (account_id, as_of_date, balance) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-01', 1000);
insert into public.income_sources (name, frequency, anchor_date, expected_net, deposit_account_id) values
  ('Job', 'biweekly', '2026-03-06', 2000, 'a0000000-0000-0000-0000-000000000001');
insert into public.envelopes (kind, name) values ('rainy_day', 'Rainy-day fund'), ('locked_savings', 'Locked savings');
insert into public.set_asides (id, name, per_paycheck, start_date, opening_balance) values
  ('5a000000-0000-0000-0000-000000000001', 'Car', 0, '2026-03-01', 600),
  ('5a000000-0000-0000-0000-000000000002', 'Overspent', 0, '2026-03-01', -200);

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select results_eq(
  $$select name, balance from public.v_set_asides order by name$$,
  $$values ('Car'::text, 600.00::numeric), ('Overspent', -200.00)$$,
  'setup: Car holds 600, Overspent is at -200');
select is((select sum(estimated_balance) from public.v_account_balances where kind = 'checking'), 1000.00::numeric,
          'setup: real cash is 1000');

select throws_ok(
  format($f$select public.move_envelope_money(%L, 400.01)$f$, (select id from public.envelopes where kind = 'rainy_day')),
  'P0001', 'Envelopes cannot hold more than the cash you have after set-asides (400.00 free)',
  'a move in past cash minus set-aside balances is rejected (the negative set-aside frees nothing)');
select is(public.move_envelope_money((select id from public.envelopes where kind = 'rainy_day'), 400, 'all free cash'),
          400::numeric, 'a move in up to the free cash is accepted');
select throws_ok(
  format($f$select public.move_envelope_money(%L, 0.01)$f$, (select id from public.envelopes where kind = 'locked_savings')),
  'P0001', 'Envelopes cannot hold more than the cash you have after set-asides (0.00 free)',
  'with set-asides and envelopes covering all cash, another envelope cannot take a cent');

select is((select f.starting_cash from public.pay_period_forecast(2, 1) f where f.period_index = 1), 0.00::numeric,
          'forecast starting cash is 0, not negative: no dollar is reserved twice');

select is(public.move_envelope_money((select id from public.envelopes where kind = 'rainy_day'), -100, 'draw'),
          300::numeric, 'moving out is unaffected by set-asides');
select lives_ok(
  format($f$select public.move_envelope_money(%L, 100)$f$, (select id from public.envelopes where kind = 'locked_savings')),
  'the freed 100 can go into another envelope');

reset role;
update public.set_asides set is_active = false where name = 'Car';
set local role authenticated;
select lives_ok(
  format($f$select public.move_envelope_money(%L, 600)$f$, (select id from public.envelopes where kind = 'locked_savings')),
  'an inactive set-aside no longer holds cash');
select throws_like(
  format($f$select public.move_envelope_money(%L, 0.01)$f$, (select id from public.envelopes where kind = 'rainy_day')),
  'Envelopes cannot hold more than the cash you have%', 'the cap still holds with no active set-asides');

reset role;
select ok(has_function_privilege('authenticated', 'public.move_envelope_money(uuid,numeric,text,date)', 'execute')
      and not has_function_privilege('anon', 'public.move_envelope_money(uuid,numeric,text,date)', 'execute'),
          'grants unchanged: authenticated yes, anon no');

select * from finish();
rollback;
