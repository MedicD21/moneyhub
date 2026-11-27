-- v_pay_period_forecast reserve_to / reserve_unassigned / reserve_from / reserve_unfunded
-- (migration 20261127180000_forecast_reserve_flows.sql).
--
-- Biweekly pay $2000 with big irregular bills so some periods hold money back and later ones draw on it.
-- The attribution is first in, first out; these tests check its invariants and the exact split.
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
  ('a0000000-0000-0000-0000-000000000001', '2026-03-09', 3000);
insert into public.income_sources (name, frequency, anchor_date, expected_net, deposit_account_id) values
  ('Job', 'biweekly', '2026-03-06', 2000, 'a0000000-0000-0000-0000-000000000001');
insert into public.transactions (account_id, txn_date, description_raw, amount, category_id) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-06', 'PAYROLL', 2000, (select id from public.categories where name = 'Income'));
insert into public.bills (id, name, amount, is_variable, frequency, due_day, anchor_date) values
  ('e0000000-0000-0000-0000-000000000001', 'Rent',      900, false, 'monthly', 15, null),
  ('e0000000-0000-0000-0000-000000000002', 'Insurance', 2600, false, 'annual', null, '2025-04-24'),
  ('e0000000-0000-0000-0000-000000000003', 'Tax',       2300, false, 'annual', null, '2025-05-22');
select public.ensure_bill_occurrences('2026-03-31');

select diag(coalesce(string_agg(format('%s %s hold=%s carry=%s to=%s unassigned=%s from=%s unfunded=%s', period_index, period_start,
       hold_for_later, carry_out, reserve_to, reserve_unassigned, reserve_from, reserve_unfunded), E'\n' order by period_index), 'none'))
  from public.v_pay_period_forecast;

-- every reserve contribution is fully accounted for: assigned to draws plus unassigned
-- (period 1 contributes its leftover cash, carry_out; later periods contribute hold_for_later)
select is((select count(*)::int from public.v_pay_period_forecast f
            where f.reserve_unassigned is not null
              and (case when f.period_index = 1 then f.carry_out else f.hold_for_later end)
                  <> f.reserve_unassigned
                     + coalesce((select sum((x->>'amount')::numeric) from jsonb_array_elements(f.reserve_to) x), 0)),
          0, 'each contribution = assigned to later draws + unassigned');

-- every draw (after the current period) is fully accounted for: funded plus unfunded
select is((select count(*)::int from public.v_pay_period_forecast f
            where f.hold_for_later < 0 and f.period_index > 1
              and -f.hold_for_later <> f.reserve_unfunded
                  + coalesce((select sum((x->>'amount')::numeric) from jsonb_array_elements(f.reserve_from) x), 0)),
          0, 'each draw = funded by earlier periods + unfunded');

-- money only flows forward in time
select is((select count(*)::int from public.v_pay_period_forecast f, jsonb_array_elements(f.reserve_to) x
            where (x->>'period_index')::int <= f.period_index),
          0, 'held-back money only funds later periods');

-- the two sides agree: total assigned out = total funded in
select is((select coalesce(sum((x->>'amount')::numeric), 0) from public.v_pay_period_forecast f, jsonb_array_elements(f.reserve_to) x),
          (select coalesce(sum((x->>'amount')::numeric), 0) from public.v_pay_period_forecast f, jsonb_array_elements(f.reserve_from) x),
          'what held-back periods send out equals what drawing periods receive');

-- existing forecast columns are untouched: carry_out still chains as previous carry_out + hold_for_later (period 2 onward)
select is((select count(*)::int from (
             select f.period_index, f.carry_out,
                    lag(f.carry_out) over (order by f.period_index) + f.hold_for_later as chained
             from public.v_pay_period_forecast f) t
            where t.period_index > 2 and abs(t.carry_out - t.chained) > 0.02),
          0, 'carry_out still chains from hold_for_later (forecast math unchanged)');

-- with the opening reserve counted, every draw is covered (rounding aside)
select is((select count(*)::int from public.v_pay_period_forecast where reserve_unfunded > 0.02),
          0, 'every draw is fully funded by earlier money');

-- exact split in this fixture: period 4 (04-17) draws 1483.33 = period 1's 1216.67 leftover cash + 266.66 from the 03-20 paycheck
select results_eq(
  $$select (x->>'period_index')::int, (x->>'amount')::numeric
      from public.v_pay_period_forecast f, jsonb_array_elements(f.reserve_from) x
     where f.period_index = 4 order by 1$$,
  $$values (1, 1216.67::numeric), (2, 266.66::numeric)$$,
  'first in, first out split for the first draw');

-- there is at least one real draw funded by an earlier period in this fixture
select ok(exists (select 1 from public.v_pay_period_forecast where jsonb_array_length(reserve_from) > 0),
          'fixture produces a draw funded from an earlier period');

-- first in, first out: the first draw starts with the oldest money, the current period's leftover cash
select is((select (reserve_from->0->>'period_index')::int from public.v_pay_period_forecast
            where jsonb_array_length(reserve_from) > 0 order by period_index limit 1),
          1, 'first draw starts with the current period''s leftover cash');

-- signed-in owner can read the new columns; anon cannot read the view
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select ok((select count(*) from public.v_pay_period_forecast where reserve_to is not null) > 0, 'authenticated owner reads the new columns');
reset role;
select ok(not has_table_privilege('anon', 'public.v_pay_period_forecast', 'select'), 'anon still cannot read the view');

select * from finish();
rollback;
