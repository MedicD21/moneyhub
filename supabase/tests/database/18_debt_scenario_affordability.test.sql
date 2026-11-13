-- Affordability layer of simulate_debt_plan (20261113070000). Same statement-verified fixture as test 17.
-- Isolated transaction; no production writes. Money figures below are computed by the database, not the browser.
begin;
create extension if not exists pgtap with schema extensions;
grant execute on all functions in schema extensions to anon, authenticated;
select no_plan();
truncate public.app_settings, public.debts, public.bills, public.income_sources, public.debt_plans cascade;
insert into auth.users(id,email) values ('11111111-1111-1111-1111-111111111111','sim-owner@test.local') on conflict do nothing;
insert into public.app_settings(owner_id) values ('11111111-1111-1111-1111-111111111111');
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
create temp table fixture(data jsonb);
insert into fixture values ($fixture${"debts":[{"id":"5aa25395-3701-4611-a20d-36c31ecd1777","name":"Synchrony LoveSac","apr":0,"min_payment":105,"balance":380,"frequency":"monthly","due_day":10},{"id":"b7ad4d3c-0c03-4b68-b7a1-4a33c5e18d09","name":"Affirm \u2013 Mattress","apr":35.98,"min_payment":188.93,"balance":1630.02,"frequency":"monthly","due_day":28},{"id":"4ff8d14d-7c85-49bb-9e71-38f1e39ebb8f","name":"Affirm \u2013 farmgirlflowers","apr":35.98,"min_payment":14.06,"balance":49.9,"frequency":"monthly","due_day":17},{"id":"ef7a28d4-64cc-443d-a0ad-84447d996b34","name":"Affirm \u2013 PIPER-JOINPOLLY","apr":32.91,"min_payment":84.94,"balance":1358.99,"frequency":"monthly","due_day":2},{"id":"c3cc26b7-3aef-439b-a636-e6fa64e17859","name":"Affirm \u2013 Alls","apr":35.98,"min_payment":16.61,"balance":82.45,"frequency":"monthly","due_day":21},{"id":"5003b518-e48f-438a-8a1e-14c59187cd79","name":"Affirm \u2013 Amazon (7th)","apr":27.39,"min_payment":15.48,"balance":92.91,"frequency":"monthly","due_day":7},{"id":"828988e4-c894-4317-8d15-f84f9a09c271","name":"Affirm \u2013 Crown","apr":35.98,"min_payment":72.7,"balance":1254.98,"frequency":"monthly","due_day":30},{"id":"156dff81-4895-47c1-a0e6-38c3a8fd351a","name":"Ally Auto / Gladiator","apr":8.34,"min_payment":782.95,"balance":31874.12,"frequency":"monthly","due_day":12},{"id":"4744ee7e-bc25-4589-bf6f-c397e42c61e8","name":"Affirm \u2013 Nintendo","apr":35.96,"min_payment":16.06,"balance":63.51,"frequency":"monthly","due_day":11},{"id":"75499e11-b9df-4e65-aacd-45a1f6eeb6a6","name":"Affirm \u2013 Amazon (13th)","apr":29.95,"min_payment":11.57,"balance":69.4,"frequency":"monthly","due_day":13},{"id":"26c2c2cf-e73d-4553-8c17-033163fe5227","name":"Affirm \u2013 Whatnot","apr":35.81,"min_payment":15.83,"balance":31.66,"frequency":"monthly","due_day":14},{"id":"97c7d6bd-e3f0-4e93-a40a-8819ab381ca9","name":"Synchrony Mattress Firm","apr":0,"min_payment":56,"balance":1328,"frequency":"monthly","due_day":18},{"id":"e4087555-07b4-4141-95fb-d5b7ab8db92e","name":"GoodLeap","apr":11.49,"min_payment":39.13,"balance":2335.59,"frequency":"monthly","due_day":21},{"id":"fe50d3b8-930a-4974-9899-e80b1500bca4","name":"Apple Card","apr":25.74,"min_payment":112,"balance":3491.42,"frequency":"monthly","due_day":30},{"id":"5921562e-2080-4140-8ab3-d5b5d35a92b1","name":"Amazon Store Card","apr":29.99,"min_payment":42,"balance":1177.75,"frequency":"monthly","due_day":13},{"id":"79a3871c-01c6-4f78-8fe5-599290980585","name":"Spark credit card","apr":27.74,"min_payment":64,"balance":1894.52,"frequency":"monthly","due_day":8},{"id":"e787148d-e062-4763-9c6a-ae4e4c381fef","name":"Home Depot","apr":23.61,"min_payment":138,"balance":4530.03,"frequency":"monthly","due_day":22},{"id":"466ed164-273e-42ca-8a2e-fa10ebf33377","name":"SoFi credit card","apr":22.74,"min_payment":131,"balance":4180.43,"frequency":"monthly","due_day":5}],"plan":{"name":"Avalanche + rollover (statement-verified)","strategy":"avalanche","extra_monthly":0,"balances_as_of":"2026-11-12","assumptions":{"ally":"Dec 2026 extension payment 195.75, then 782.95","sofi":"22.74% APR and $10 monthly fee, both from the 11/10 statement","affirm":"modeled at 0% on fixed schedules; balances already include future interest","lovesac":"balance 380.00 until the returned $105 payment is retried","goodleap":"11.49% interest-bearing","rollover":"payments from paid-off debts move to the next target, starting the month after payoff","home_depot":"blended 23.61% APR from the 10/26 statement (29.99% on 1753.48, 25.99% on 2092.31, 0% promo on 684.24 with no expiration shown); buckets not modeled separately","new_charges":"assumed to stop","start_month":"2026-11","target_order":"highest APR first among cards and Ally; 0% debts stay on minimums; Affirm plans run on schedule","card_balances":"statement/app-verified 2026-11-12","card_minimums":"held at current amounts","interest_start":"December 2026 (November covers remaining Nov payments only)","monthly_payment_total":1906.26},"summary":{"total_interest":10489.51,"debt_free_month":"2029-10","interest_saved_vs_minimums":6615.09,"months_earlier_than_minimums":52},"schedule":[{"end":31874.12,"month":"2026-11","start":31874.12,"debt_id":"156dff81-4895-47c1-a0e6-38c3a8fd351a","minimum":0,"payment":0,"interest":0},{"end":4392.03,"month":"2026-11","start":4530.03,"debt_id":"e787148d-e062-4763-9c6a-ae4e4c381fef","minimum":138,"payment":138,"interest":0},{"end":4180.43,"month":"2026-11","start":4180.43,"debt_id":"466ed164-273e-42ca-8a2e-fa10ebf33377","minimum":0,"payment":0,"interest":0},{"end":3379.42,"month":"2026-11","start":3491.42,"debt_id":"fe50d3b8-930a-4974-9899-e80b1500bca4","minimum":112,"payment":112,"interest":0},{"end":2296.46,"month":"2026-11","start":2335.59,"debt_id":"e4087555-07b4-4141-95fb-d5b7ab8db92e","minimum":39.13,"payment":39.13,"interest":0},{"end":1894.52,"month":"2026-11","start":1894.52,"debt_id":"79a3871c-01c6-4f78-8fe5-599290980585","minimum":0,"payment":0,"interest":0},{"end":1441.09,"month":"2026-11","start":1630.02,"debt_id":"b7ad4d3c-0c03-4b68-b7a1-4a33c5e18d09","minimum":188.93,"payment":188.93,"interest":0},{"end":1358.99,"month":"2026-11","start":1358.99,"debt_id":"ef7a28d4-64cc-443d-a0ad-84447d996b34","minimum":0,"payment":0,"interest":0},{"end":1272,"month":"2026-11","start":1328,"debt_id":"97c7d6bd-e3f0-4e93-a40a-8819ab381ca9","minimum":56,"payment":56,"interest":0},{"end":1182.28,"month":"2026-11","start":1254.98,"debt_id":"828988e4-c894-4317-8d15-f84f9a09c271","minimum":72.7,"payment":72.7,"interest":0},{"end":1135.75,"month":"2026-11","start":1177.75,"debt_id":"5921562e-2080-4140-8ab3-d5b5d35a92b1","minimum":42,"payment":42,"interest":0},{"end":275,"month":"2026-11","start":380,"debt_id":"5aa25395-3701-4611-a20d-36c31ecd1777","minimum":105,"payment":105,"interest":0},{"end":92.91,"month":"2026-11","start":92.91,"debt_id":"5003b518-e48f-438a-8a1e-14c59187cd79","minimum":0,"payment":0,"interest":0},{"end":65.84,"month":"2026-11","start":82.45,"debt_id":"c3cc26b7-3aef-439b-a636-e6fa64e17859","minimum":16.61,"payment":16.61,"interest":0},{"end":57.83,"month":"2026-11","start":69.4,"debt_id":"75499e11-b9df-4e65-aacd-45a1f6eeb6a6","minimum":11.57,"payment":11.57,"interest":0},{"end":63.51,"month":"2026-11","start":63.51,"debt_id":"4744ee7e-bc25-4589-bf6f-c397e42c61e8","minimum":0,"payment":0,"interest":0},{"end":35.84,"month":"2026-11","start":49.9,"debt_id":"4ff8d14d-7c85-49bb-9e71-38f1e39ebb8f","minimum":14.06,"payment":14.06,"interest":0},{"end":15.83,"month":"2026-11","start":31.66,"debt_id":"26c2c2cf-e73d-4553-8c17-033163fe5227","minimum":15.83,"payment":15.83,"interest":0},{"end":31899.9,"month":"2026-12","start":31874.12,"debt_id":"156dff81-4895-47c1-a0e6-38c3a8fd351a","minimum":195.75,"payment":195.75,"interest":221.53},{"end":4340.44,"month":"2026-12","start":4392.03,"debt_id":"e787148d-e062-4763-9c6a-ae4e4c381fef","minimum":138,"payment":138,"interest":86.41},{"end":4138.65,"month":"2026-12","start":4180.43,"debt_id":"466ed164-273e-42ca-8a2e-fa10ebf33377","minimum":131,"payment":131,"interest":89.22},{"end":3339.91,"month":"2026-12","start":3379.42,"debt_id":"fe50d3b8-930a-4974-9899-e80b1500bca4","minimum":112,"payment":112,"interest":72.49},{"end":2279.32,"month":"2026-12","start":2296.46,"debt_id":"e4087555-07b4-4141-95fb-d5b7ab8db92e","minimum":39.13,"payment":39.13,"interest":21.99},{"end":1874.31,"month":"2026-12","start":1894.52,"debt_id":"79a3871c-01c6-4f78-8fe5-599290980585","minimum":64,"payment":64,"interest":43.79},{"end":1252.16,"month":"2026-12","start":1441.09,"debt_id":"b7ad4d3c-0c03-4b68-b7a1-4a33c5e18d09","minimum":188.93,"payment":188.93,"interest":0},{"end":1274.05,"month":"2026-12","start":1358.99,"debt_id":"ef7a28d4-64cc-443d-a0ad-84447d996b34","minimum":84.94,"payment":84.94,"interest":0},{"end":1216,"month":"2026-12","start":1272,"debt_id":"97c7d6bd-e3f0-4e93-a40a-8819ab381ca9","minimum":56,"payment":56,"interest":0},{"end":1109.58,"month":"2026-12","start":1182.28,"debt_id":"828988e4-c894-4317-8d15-f84f9a09c271","minimum":72.7,"payment":72.7,"interest":0},{"end":1122.13,"month":"2026-12","start":1135.75,"debt_id":"5921562e-2080-4140-8ab3-d5b5d35a92b1","minimum":42,"payment":42,"interest":28.38},{"end":170,"month":"2026-12","start":275,"debt_id":"5aa25395-3701-4611-a20d-36c31ecd1777","minimum":105,"payment":105,"interest":0},{"end":77.43,"month":"2026-12","start":92.91,"debt_id":"5003b518-e48f-438a-8a1e-14c59187cd79","minimum":15.48,"payment":15.48,"interest":0},{"end":49.23,"month":"2026-12","start":65.84,"debt_id":"c3cc26b7-3aef-439b-a636-e6fa64e17859","minimum":16.61,"payment":16.61,"interest":0},{"end":46.26,"month":"2026-12","start":57.83,"debt_id":"75499e11-b9df-4e65-aacd-45a1f6eeb6a6","minimum":11.57,"payment":11.57,"interest":0},{"end":47.45,"month":"2026-12","start":63.51,"debt_id":"4744ee7e-bc25-4589-bf6f-c397e42c61e8","minimum":16.06,"payment":16.06,"interest":0},{"end":21.78,"month":"2026-12","start":35.84,"debt_id":"4ff8d14d-7c85-49bb-9e71-38f1e39ebb8f","minimum":14.06,"payment":14.06,"interest":0},{"end":0,"month":"2026-12","start":15.83,"debt_id":"26c2c2cf-e73d-4553-8c17-033163fe5227","minimum":15.83,"payment":15.83,"interest":0}]}}$fixture$);
insert into public.debts(id,name,kind,apr,min_payment,due_day)
select (v->>'id')::uuid,v->>'name','personal',(v->>'apr')::numeric,(v->>'min_payment')::numeric,(v->>'due_day')::int
from fixture,jsonb_array_elements(data->'debts') v;
insert into public.debt_balances(debt_id,as_of_date,balance,created_at)
select (v->>'id')::uuid,'2026-11-12',(v->>'balance')::numeric,'2026-11-12 23:00Z'
from fixture,jsonb_array_elements(data->'debts') v;
-- Same-day LoveSac rows: the latest created_at must win, regardless of amount.
insert into public.debt_balances(debt_id,as_of_date,balance,created_at) values
('5aa25395-3701-4611-a20d-36c31ecd1777','2026-11-12',3635,'2026-11-12 01:00Z'),
('5aa25395-3701-4611-a20d-36c31ecd1777','2026-11-12',275,'2026-11-12 02:00Z');
insert into public.bills(name,amount,frequency,due_day,debt_id)
select name,min_payment,'monthly',due_day,id from public.debts;
insert into public.income_sources(name,frequency,anchor_date,expected_net) values ('Test payroll','biweekly','2026-11-13',2000);
insert into public.bills(name,amount,frequency,due_day) values ('Test subscription',25,'monthly',15);
insert into public.debt_plans(name,strategy,extra_monthly,assumptions,summary,schedule,balances_as_of,is_active)
select data->'plan'->>'name','avalanche',0,data->'plan'->'assumptions',data->'plan'->'summary',data->'plan'->'schedule','2026-11-12',true from fixture;
select set_config('app.today','2026-11-13',true);
insert into public.accounts(name,kind,balance_includes_pending) values ('Test checking','checking',false);
insert into public.balance_snapshots(account_id,as_of_date,balance) select id,'2026-11-13',2000 from public.accounts;
create temp table r(label text primary key, res jsonb);
insert into r values
 ('base',public.simulate_debt_plan()),
 ('lump',public.simulate_debt_plan('{"lump_sums":[{"date":"2026-11-14","amount":10000}]}')),
 ('payoff',public.simulate_debt_plan('{"payoff_now":["e4087555-07b4-4141-95fb-d5b7ab8db92e"]}')),
 ('ot',public.simulate_debt_plan('{"overtime":[{"pay_date":"2026-11-27","hours":10}]}')),
 ('raise',public.simulate_debt_plan('{"raise":{"effective_date":"2026-11-20","extra_net_per_paycheck":100}}')),
 ('bill',public.simulate_debt_plan('{"drop_payment":[{"label":"Test subscription","from_month":"2026-12"}]}'));
create function pg_temp.period(p_label text, p_index int, p_key text) returns numeric language sql as $$
  select (p->>p_key)::numeric from r, jsonb_array_elements(res->'affordability'->'periods') p
  where label=p_label and (p->>'period_index')::int=p_index $$;

-- Shape: the original simulation is still returned, with the new keys appended.
select ok((select res ?& array['schedule','summary','monthly_balances','defaults','affordability'] from r where label='base'),'result keeps schedule and summary and adds monthly_balances, defaults, affordability');
select is((select res#>>'{defaults,strategy}' from r where label='base'),'avalanche','defaults report the active plan strategy');
select is((select res#>>'{defaults,start_month}' from r where label='base'),'2026-11','defaults report the plan start month');
select is((select jsonb_array_length(res->'monthly_balances') from r where label='base'),
 (select count(distinct s->>'month')::int from r, jsonb_array_elements(res->'schedule') s where label='base'),'one monthly balance row per scheduled month');
select is((select (m->>'balance')::numeric from r, jsonb_array_elements(res->'monthly_balances') m where label='base' and m->>'month'='2026-11'),
 (select sum((s->>'end')::numeric) from r, jsonb_array_elements(res->'schedule') s where label='base' and s->>'month'='2026-11'),'monthly balance equals the sum of that month''s schedule ends');
select is((select (m->>'opening_balance')::numeric from r, jsonb_array_elements(res->'monthly_balances') m where label='base' and m->>'month'='2026-11'),
 (select sum((s->>'start')::numeric) from r, jsonb_array_elements(res->'schedule') s where label='base' and s->>'month'='2026-11'),'monthly opening balance equals the sum of schedule starts');

-- Unchanged plan: assessed, nothing flagged.
select is((select res#>>'{affordability,status}' from r where label='base'),'within_forecast','active plan is within the forecast');
select is((select jsonb_array_length(res->'affordability'->'periods') from r where label='base'),7,'seven forecast periods are assessed');
select is((select res#>>'{affordability,flagged_periods}' from r where label='base'),'0','no periods flagged for the active plan');
select is((select res#>>'{affordability,from_date}' from r where label='base'),'2026-11-13','assessment starts today');
select is((select res#>>'{affordability,full_plan_checked}' from r where label='base'),'false','never claims the whole plan was checked');

-- Lump sum larger than cash: flagged, with a gap and no rainy-day reserve assumed.
select is((select res#>>'{affordability,status}' from r where label='lump'),'at_risk','oversized lump sum is at risk');
select ok((select (res#>>'{affordability,flagged_periods}')::int>0 and (res#>>'{affordability,cash_shortfall_periods}')::int>0 from r where label='lump'),'oversized lump sum flags periods and a cash shortfall');
select is(pg_temp.period('lump',1,'lump_cash'),10000::numeric,'lump cash is charged to the period holding its date');
select ok((select (res#>>'{affordability,peak_gap}')::numeric>0 from r where label='lump'),'peak gap is positive');
select ok((select coalesce(jsonb_typeof(res#>'{affordability,rainy_day}'),'null')='null' from r where label='lump'),'no rainy-day reserve is assumed when none exists');
select is((select (res#>>'{affordability,remaining_gap}')::numeric from r where label='lump'),(select (res#>>'{affordability,peak_gap}')::numeric from r where label='lump'),'without a reserve the whole gap remains');

-- Payoff nobody funded is labelled, never called affordable.
select is((select res#>>'{affordability,status}' from r where label='payoff'),'unfunded_what_if','unfunded payoff is labelled');
select is((select (res#>>'{affordability,unfunded_payoff}')::numeric from r where label='payoff'),2335.59::numeric,'unfunded payoff equals the removed balance');

-- Income arrives only in its own pay period.
select is(pg_temp.period('ot',2,'added_income'),268.00::numeric,'10 overtime hours add hours x extra_hour_net in the pay period holding that date');
select is(pg_temp.period('ot',1,'added_income'),0::numeric,'overtime income is not pulled into an earlier period');
select is(pg_temp.period('raise',1,'added_income'),0::numeric,'raise does not apply before its effective date');
select is(pg_temp.period('raise',2,'added_income'),100.00::numeric,'raise counts one paycheck in the next period');
select is(pg_temp.period('raise',3,'added_income'),100.00::numeric,'raise counts the following paycheck too');

-- Stopped payments are credited once, in the period the bill falls due.
select is(pg_temp.period('bill',3,'released_obligations')-pg_temp.period('base',3,'released_obligations'),25.00::numeric,'stopping a standalone bill releases its amount in the period it is due');
select is(pg_temp.period('bill',2,'released_obligations')-pg_temp.period('base',2,'released_obligations'),0::numeric,'nothing is released before the stop month');

-- Rainy-day reserve: suggested draw is capped by the balance; nothing is moved.
insert into public.envelopes(kind,name) values ('rainy_day','Rainy-day fund');
insert into public.envelope_moves(envelope_id,amount,move_date) select id,500,'2026-11-13' from public.envelopes where kind='rainy_day';
create temp table rr as select public.simulate_debt_plan('{"lump_sums":[{"date":"2026-11-14","amount":10000}]}') res;
select is((select (res#>>'{affordability,rainy_day,rainy_balance}')::numeric from rr),500::numeric,'reserve balance comes from the rainy-day envelope');
select is((select (res#>>'{affordability,suggested_draw}')::numeric from rr),least(500::numeric,(select (res#>>'{affordability,peak_gap}')::numeric from rr)),'suggested draw is the smaller of the reserve and the gap');
select is((select (res#>>'{affordability,remaining_gap}')::numeric from rr),greatest((select (res#>>'{affordability,peak_gap}')::numeric from rr)-500,0),'remaining gap is what the reserve cannot cover');
select is((select count(*)::int from public.envelope_moves),1,'simulation moves no envelope money');

-- Permissions, ownership and read-only behaviour.
select ok(not has_function_privilege('authenticated','public._debt_scenario_context(jsonb,jsonb)','execute'),'context helper not callable by the browser');
select ok(not has_function_privilege('anon','public._debt_scenario_context(jsonb,jsonb)','execute'),'context helper not callable anonymously');
select ok(has_function_privilege('authenticated','public.simulate_debt_plan(jsonb)','execute'),'signed-in owner may still call the simulator');
select ok(not has_function_privilege('anon','public.simulate_debt_plan(jsonb)','execute'),'anonymous role still cannot call the simulator');
select is((select provolatile::text from pg_proc where oid='public.simulate_debt_plan(jsonb)'::regprocedure),'s','simulator is still STABLE');
set local role authenticated;
select lives_ok($$select public.simulate_debt_plan('{"extra_monthly":100}')$$,'authenticated owner gets affordability');
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',true);
select throws_ok($$select public.simulate_debt_plan()$$,'42501','Not signed in as the Money Hub owner','other user denied');
reset role;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
set local transaction_read_only=on;
select lives_ok($$select public.simulate_debt_plan('{"lump_sums":[{"date":"2026-11-14","amount":10000}]}')$$,'affordability runs inside a READ ONLY transaction');
select * from finish();
rollback;
