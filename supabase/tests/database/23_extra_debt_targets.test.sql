-- extra_debt item targets in paycheck_plan() (migration 20261127200000_extra_debt_targets.sql).
--
-- Today 2026-03-10; biweekly pay anchored 2026-03-06 (period 03-06 .. 03-19, 26 paydays a year).
-- Active plan, March 2026 schedule rows (payment above minimum): Visa +30.00, Car loan +10.00 => 40.00 extra a month.
-- Per paycheck: round(40 * 12 / 26, 2) = 18.46, split 75% / 25% -> Visa 13.85 (rounded), Car loan takes the remainder 4.61.
begin;
create extension if not exists pgtap with schema extensions;
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans cascade;
grant execute on all functions in schema extensions to anon, authenticated;
select plan(7);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-10';

insert into public.accounts (id, name, kind) values ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking');
insert into public.income_sources (name, frequency, anchor_date, expected_net, deposit_account_id) values
  ('Job', 'biweekly', '2026-03-06', 2000, 'a0000000-0000-0000-0000-000000000001');
insert into public.debts (id, name, kind, apr, min_payment, due_day) values
  ('d0000000-0000-0000-0000-000000000001', 'Visa',     'credit_card', 24.99,  35, 12),
  ('d0000000-0000-0000-0000-000000000002', 'Car loan', 'auto',         6.90, 300, 17),
  ('d0000000-0000-0000-0000-000000000003', 'Paid off', 'other',        0.00,  10, 20);
insert into public.debt_plans (name, strategy, extra_monthly, assumptions, summary, schedule, balances_as_of, is_active)
values ('Avalanche', 'avalanche', 0, '{}', '{}', jsonb_build_array(
  jsonb_build_object('month', '2026-03', 'debt_id', 'd0000000-0000-0000-0000-000000000001', 'minimum', 35,  'payment', 65,  'interest', 0, 'start', 1000, 'end', 935),
  jsonb_build_object('month', '2026-03', 'debt_id', 'd0000000-0000-0000-0000-000000000002', 'minimum', 300, 'payment', 310, 'interest', 0, 'start', 5000, 'end', 4690),
  jsonb_build_object('month', '2026-03', 'debt_id', 'd0000000-0000-0000-0000-000000000003', 'minimum', 10,  'payment', 10,  'interest', 0, 'start', 10, 'end', 0),
  jsonb_build_object('month', '2026-04', 'debt_id', 'd0000000-0000-0000-0000-000000000001', 'minimum', 35,  'payment', 35,  'interest', 0, 'start', 935, 'end', 900)),
  '2026-03-01', true);

select is((select extra_debt from public.paycheck_plan()), 18.46::numeric, 'extra debt per paycheck is unchanged: 40 x 12 / 26');

select results_eq(
  $$select e->>'name', (e->>'amount')::numeric from public.paycheck_plan() p, jsonb_array_elements(p.items) i, jsonb_array_elements(i->'targets') e
     where i->>'type' = 'extra_debt' order by (e->>'amount')::numeric desc$$,
  $$values ('Visa'::text, 13.85::numeric), ('Car loan'::text, 4.61::numeric)$$,
  'targets name each debt that gets extra, largest first');

select is((select sum((e->>'amount')::numeric) from public.paycheck_plan() p, jsonb_array_elements(p.items) i, jsonb_array_elements(i->'targets') e
            where i->>'type' = 'extra_debt'),
          (select extra_debt from public.paycheck_plan()),
          'targets add up exactly to the extra debt payment');

select is((select jsonb_array_length(i->'targets') from public.paycheck_plan() p, jsonb_array_elements(p.items) i where i->>'type' = 'extra_debt'),
          2, 'a debt paid at its minimum is not a target');

-- the next month the plan only pays the Visa above its minimum (not at all above minimum: payment = minimum), so no extra item
select is((select extra_debt from public.paycheck_plan('2026-04-03')), 0::numeric, 'no extra debt (and no item) when the plan pays only minimums');
select is((select count(*)::int from public.paycheck_plan('2026-04-03') p, jsonb_array_elements(p.items) i where i->>'type' = 'extra_debt'),
          0, 'no extra_debt item that month');

select ok(not has_function_privilege('anon', 'public.debt_plan_extra_split(date,numeric,numeric)', 'execute'), 'anon cannot call the split helper');

select * from finish();
rollback;
