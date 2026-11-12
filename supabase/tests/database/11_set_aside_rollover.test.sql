-- Set-aside rollover: balance builds each payday, is capped, and draws down from tagged / categorized spending.
--
-- Today 2026-03-10. Biweekly pay anchored Fri 2026-03-06 (paydays 03-06, 03-20, 04-03, 04-17, 05-01).
-- Set-aside "Car": 50 per paycheck, cap 120, linked to the Gas category, starts 03-06.
-- Draws: Gas 30 (03-08, by category) + Misc 10 (03-09, tagged by set_aside_id) = 40.
--   03-06  before   0  +50 -> 50
--   03-20  before  10  +50 -> 60   (50 - 40 drawn)
--   04-03  before  60  +50 -> 110
--   04-17  before 110  +10 -> 120   (cap shrinks the contribution)
--   05-01  before 120  + 0 -> 120
begin;
create extension if not exists pgtap with schema extensions;
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans cascade;
select plan(7);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-10';

insert into public.accounts (id, name, kind) values ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking');
insert into public.income_sources (name, frequency, anchor_date, expected_net, deposit_account_id) values
  ('Job', 'biweekly', '2026-03-06', 2000, 'a0000000-0000-0000-0000-000000000001');

insert into public.set_asides (id, name, per_paycheck, cap, start_date, category_id) values
  ('5a000000-0000-0000-0000-000000000001', 'Car', 50, 120, '2026-03-06',
   (select id from public.categories where name = 'Gas'));

insert into public.transactions (account_id, txn_date, description_raw, amount, category_id, set_aside_id) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-06', 'PAYROLL', 2000, (select id from public.categories where name = 'Income'), null),
  ('a0000000-0000-0000-0000-000000000001', '2026-03-08', 'SHELL', -30, (select id from public.categories where name = 'Gas'), null),
  ('a0000000-0000-0000-0000-000000000001', '2026-03-09', 'OIL CHANGE', -10, (select id from public.categories where name = 'Misc'),
     '5a000000-0000-0000-0000-000000000001'),
  ('a0000000-0000-0000-0000-000000000001', '2026-03-09', 'KROGER', -20, (select id from public.categories where name = 'Groceries'), null);

select results_eq(
  $$select pay_date, balance_before, contribution, balance_after
      from public.set_aside_ledger('5a000000-0000-0000-0000-000000000001', '2026-05-01') order by pay_date$$,
  $$values ('2026-03-06'::date, 0::numeric, 50::numeric, 50::numeric),
           ('2026-03-20', 10, 50, 60),
           ('2026-04-03', 60, 50, 110),
           ('2026-04-17', 110, 10, 120),
           ('2026-05-01', 120, 0, 120)$$,
  'balance builds per payday, draws reduce it, and the cap shrinks then stops contributions');

select results_eq(
  $$select balance, current_contribution from public.set_aside_position('5a000000-0000-0000-0000-000000000001')$$,
  $$values (10.00::numeric, 50.00::numeric)$$,
  'position today: 50 after this payday minus 40 drawn');

select results_eq(
  $$select balance, room_left, at_cap from public.v_set_asides$$,
  $$values (10.00::numeric, 110.00::numeric, false)$$,
  'v_set_asides exposes balance and room left');

select results_eq(
  $$select set_asides_total from public.paycheck_plan()$$,
  $$values (50.00::numeric)$$,
  'current period contribution is the full 50');
select results_eq(
  $$select set_asides_total, (select (i->>'capped')::boolean from jsonb_array_elements(pp.items) i where i->>'type' = 'set_aside')
      from public.paycheck_plan('2026-04-17') pp$$,
  $$values (10.00::numeric, true)$$,
  'a capped period contributes only the room left and flags the item as capped');
select results_eq(
  $$select spent_so_far from public.paycheck_plan()$$,
  $$values (20.00::numeric)$$,
  'spending drawn from a set-aside (tagged or by category) is not discretionary spending');

-- inactive set-asides contribute nothing
update public.set_asides set is_active = false;
select results_eq(
  $$select set_asides_total from public.paycheck_plan()$$,
  $$values (0.00::numeric)$$,
  'inactive set-asides do not contribute');

select * from finish();
rollback;
