-- Shortfall planner (migration 20261127210000_shortfall_planner.sql).
--
-- Same fixture as 20_daily_balance_forecast: today 2026-03-10, biweekly pay 2026-03-06 (2000 net),
-- cash 1000, extra_hour_net 26.80, floor 0. Scheduled-items-only balances:
--   03-10 945 | 03-15 -255 (rent, lowest; paycheck of 03-06 is already past) | 03-20 +2000 -> 1745
--   03-25 1675 | 03-27 -125 | 04-01 -140 (lowest of the 03-20 window)
-- so the 03-20 paycheck window dips 140 below the floor: ceil(140 / 26.80) = 6 extra hours, and the
-- 255 dip in the current period cannot be fixed by OT.
begin;
create extension if not exists pgtap with schema extensions;
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans, public.envelopes, public.shortfall_plans, public.pay_date_overrides cascade;
grant execute on all functions in schema extensions to anon, authenticated;
select plan(30);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
update public.app_settings set extra_hour_net = 26.80, low_balance_threshold = 0 where id;
set local app.today = '2026-03-10';

insert into public.accounts (id, name, kind) values ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking');
insert into public.balance_snapshots (account_id, as_of_date, balance) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-09', 1000);
insert into public.income_sources (name, frequency, anchor_date, expected_net, deposit_account_id) values
  ('Job', 'biweekly', '2026-03-06', 2000, 'a0000000-0000-0000-0000-000000000001');
insert into public.transactions (account_id, txn_date, description_raw, amount, category_id) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-06', 'PAYROLL', 2000, (select id from public.categories where name = 'Income'));
insert into public.bills (id, name, amount, is_variable, frequency, due_day, anchor_date) values
  ('e0000000-0000-0000-0000-000000000001', 'Rent',          1200, false, 'monthly', 15, null),
  ('e0000000-0000-0000-0000-000000000002', 'Gym',             40, false, 'monthly',  5, null),
  ('e0000000-0000-0000-0000-000000000003', 'Internet',        70, false, 'monthly', 25, null),
  ('e0000000-0000-0000-0000-000000000004', 'Car insurance', 1800, false, 'annual', null, '2025-03-27'),
  ('e0000000-0000-0000-0000-000000000005', 'Streaming',       15, false, 'monthly',  1, null);
select public.ensure_bill_occurrences('2026-03-31');

-- grants
select ok(not has_function_privilege('anon', 'public.save_shortfall_plan(jsonb)', 'execute'), 'anon cannot save a plan');
select ok(not has_function_privilege('anon', 'public.shortfall_plan_forecast(jsonb)', 'execute'), 'anon cannot read the planner');
select ok(has_function_privilege('authenticated', 'public.save_shortfall_plan(jsonb)', 'execute'), 'authenticated can save a plan');
select ok(has_function_privilege('authenticated', 'public.shortfall_plan_forecast(jsonb)', 'execute'), 'authenticated can read the planner');

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- the table is read-only from the web session
select throws_ok($$insert into public.shortfall_plans (paychecks) values ('[]')$$, '42501', null, 'the table cannot be written directly');

-- ---------------------------------------------------------------- save
select ok((select public.save_shortfall_plan('[{"pay_date":"2026-03-20","ot_hours":6,"spend":0},{"pay_date":"2026-04-03","ot_hours":0,"spend":0}]')) is not null,
          'save returns the save time');
select is((select jsonb_array_length(paychecks) from public.shortfall_plans), 1, 'rows with zero hours and zero spending are dropped');
select public.save_shortfall_plan('[{"pay_date":"2026-03-20","ot_hours":2,"spend":10.5}]');
select is((select count(*)::int from public.shortfall_plans), 1, 'saving again replaces the plan (one row per owner)');
select is((select (paychecks->0->>'ot_hours')::numeric from public.shortfall_plans), 2::numeric, 'the new plan is the one stored');

select throws_ok($$select public.save_shortfall_plan('[{"pay_date":"2026-03-20","ot_hours":-1}]')$$, 'P0001',
                 'Hours and spending cannot be negative', 'negative hours are rejected');
select throws_ok($$select public.save_shortfall_plan('[{"pay_date":"2026-03-20","ot_hours":121}]')$$, 'P0001',
                 'Overtime is at most 120 hours per paycheck', 'more than 120 hours is rejected');
select throws_ok($$select public.save_shortfall_plan('[{"pay_date":"2026-03-20","spend":1.005}]')$$, 'P0001',
                 'Hours and amounts have at most two decimal places', 'more than two decimals is rejected');
select throws_ok($$select public.save_shortfall_plan('[{"pay_date":"2026-03-20","ot_hours":1},{"pay_date":"2026-03-20","ot_hours":2}]')$$, 'P0001',
                 'A pay date can appear only once in the plan', 'a duplicate pay date is rejected');
select throws_ok($$select public.save_shortfall_plan('{"pay_date":"2026-03-20"}')$$, 'P0001',
                 'The plan must be a list of paychecks', 'a non-list plan is rejected');
select throws_ok($$select public.save_shortfall_plan('[{"ot_hours":1}]')$$, 'P0001',
                 'Each paycheck needs a valid pay date', 'a missing pay date is rejected');

-- only the owner can save
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select throws_ok($$select public.save_shortfall_plan('[]')$$, '42501', null, 'a different signed-in user cannot save a plan');
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- ---------------------------------------------------------------- read: saved plan and baseline
select is((select plan_summary->>'source' from public.shortfall_plan_forecast()), 'saved', 'no argument reads the saved plan');
select is((select (plan_summary->>'hours_planned')::numeric from public.shortfall_plan_forecast()), 2::numeric, 'the saved plan counts its hours');

select results_eq(
  $$select (plan_summary->>'baseline_lowest_balance')::numeric, (plan_summary->>'baseline_shortfall')::numeric,
           (plan_summary->>'suggested_hours_total')::int, (plan_summary->>'unfixable_shortfall')::numeric,
           (plan_summary->>'remaining_shortfall')::numeric
      from public.shortfall_plan_forecast('[]')$$,
  $$values (-255.00::numeric, 255.00::numeric, 6, 255.00::numeric, 255.00::numeric)$$,
  'no OT: lowest -255; 6 hours fix the 03-20 window; the 255 current-period dip is unfixable');

select results_eq(
  $$select p->>'status', (p->>'shortfall')::numeric, (p->>'suggested_hours')::int, (p->>'suggested_net')::numeric
      from public.shortfall_plan_forecast('[]') f, jsonb_array_elements(f.plan_periods) p where p->>'pay_date' = '2026-03-20'$$,
  $$values ('open'::text, 140.00::numeric, 6, 160.80::numeric)$$,
  'the 03-20 paycheck is open, dips 140 and is suggested 6 hours (160.80 net)');

-- ---------------------------------------------------------------- read: OT
select results_eq(
  $$select (p->>'ot_net')::numeric, (p->>'low_balance')::numeric, (p->>'suggested_hours')::int
      from public.shortfall_plan_forecast('[{"pay_date":"2026-03-20","ot_hours":6}]') f, jsonb_array_elements(f.plan_periods) p
     where p->>'pay_date' = '2026-03-20'$$,
  $$values (160.80::numeric, 20.80::numeric, 0)$$,
  '6 OT hours on 03-20 add 160.80 net, lift the window low to 20.80 and need no more hours');
select is((select (plan_summary->>'suggested_hours_total')::int from public.shortfall_plan_forecast('[{"pay_date":"2026-03-20","ot_hours":6}]')),
          0, 'summary: nothing more is suggested once the plan covers the window');
select is((select (plan_summary->>'ot_net_planned')::numeric from public.shortfall_plan_forecast('[{"pay_date":"2026-03-20","ot_hours":6}]')),
          160.80::numeric, 'summary: planned OT net');
select is((select (p->>'suggested_hours')::int
             from public.shortfall_plan_forecast('[{"pay_date":"2026-03-20","ot_hours":3}]') f, jsonb_array_elements(f.plan_periods) p
            where p->>'pay_date' = '2026-03-20'),
          3, 'a partial plan is topped up: 3 hours cover 80.40, 3 more cover the remaining 59.60 (ceil of 2.22)');

-- ---------------------------------------------------------------- read: spending
select is((select (p->>'low_balance')::numeric
             from public.shortfall_plan_forecast('[{"pay_date":"2026-03-20","spend":100}]') f, jsonb_array_elements(f.plan_periods) p
            where p->>'pay_date' = '2026-03-20'),
          -240.00::numeric, '100 of planned spending on the 03-20 period lowers that window by 100');
select results_eq(
  $$select (p->>'low_balance')::numeric, (p->>'spend_editable')::boolean
      from public.shortfall_plan_forecast('[{"pay_date":"2026-03-06","spend":50}]') f, jsonb_array_elements(f.plan_periods) p
     where p->>'pay_date' = '2026-03-06'$$,
  $$values (-305.00::numeric, true)$$,
  'spending can be planned for the current period (taken from today)');

-- ---------------------------------------------------------------- read: past paychecks take no OT
select results_eq(
  $$select (p->>'ot_hours')::numeric, (p->>'ot_replaced')::boolean, (p->>'ot_editable')::boolean
      from public.shortfall_plan_forecast('[{"pay_date":"2026-03-06","ot_hours":5}]') f, jsonb_array_elements(f.plan_periods) p
     where p->>'pay_date' = '2026-03-06'$$,
  $$values (0::numeric, true, false)$$,
  'OT on a paycheck that has already been paid is ignored, not added on top');
select throws_ok($$select * from public.shortfall_plan_forecast('[{"pay_date":"2026-03-20","ot_hours":-2}]')$$, 'P0001',
                 'Hours and spending cannot be negative', 'the read function validates a draft too');

-- ---------------------------------------------------------------- read: actual net replaces the estimate
reset role;
insert into public.pay_date_overrides (income_source_id, scheduled_date, actual_date, actual_net)
select id, '2026-04-03', '2026-04-03', 2100 from public.income_sources where name = 'Job';
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select results_eq(
  $$select p->>'status', (p->>'ot_hours')::numeric, (p->>'ot_replaced')::boolean
      from public.shortfall_plan_forecast('[{"pay_date":"2026-04-03","ot_hours":4}]') f, jsonb_array_elements(f.plan_periods) p
     where p->>'pay_date' = '2026-04-03'$$,
  $$values ('actual'::text, 0::numeric, true)$$,
  'once the real net is entered, planned OT for that paycheck is ignored (the actual already includes it)');
select ok((select (p->>'spend_room')::numeric from public.shortfall_plan_forecast('[]') f, jsonb_array_elements(f.plan_periods) p
            where p->>'pay_date' = '2026-04-17') >= 0,
          'spend_room is never negative');

select * from finish();
rollback;
