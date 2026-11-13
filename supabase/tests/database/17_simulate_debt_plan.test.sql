-- Statement-verified snapshot read on 2026-11-13. Isolated transaction; no production writes.
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
-- FIRST: independently compute the legacy golden result from the input fixture.
create temp table engine_inputs as select jsonb_agg(v || jsonb_build_object(
  'stored_apr',v->'apr','fee',case when v->>'name' ilike 'SoFi%' then 10 else 0 end,
  'nov_minimum',(select x->'minimum' from jsonb_array_elements(data->'plan'->'schedule') x where x->>'month'='2026-11' and x->>'debt_id'=v->>'id'),
  'dec_minimum',(select x->'minimum' from jsonb_array_elements(data->'plan'->'schedule') x where x->>'month'='2026-12' and x->>'debt_id'=v->>'id'))) debts
from fixture,jsonb_array_elements(data->'debts') v;
create temp table golden as select public._simulate_debt_schedule(debts,
 '{"start_month":"2026-11-01","strategy":"avalanche","extra_monthly":0,"rollover":true}', '[]',true) result from engine_inputs;
select is((select result#>>'{summary,debt_free_month}' from golden),'2029-10','golden FIRST: October 2029');
select is((select (result#>>'{summary,total_interest_and_fees}')::numeric from golden),10489.51::numeric,'golden FIRST: exact historical interest including fees');
-- Gate everything else, rather than continuing after a failed pgTAP assertion.
do $$ begin
 if (select result#>>'{summary,debt_free_month}' <> '2029-10' or abs((result#>>'{summary,total_interest_and_fees}')::numeric-10489.51)>1 from golden) then
 raise exception 'Golden regression failed'; end if;
end $$;
create temp table results(label text primary key, result jsonb);
insert into results values ('default',public.simulate_debt_plan()),
 ('minimum',public.simulate_debt_plan('{"strategy":"minimums_only"}')),
 ('zero',public.simulate_debt_plan('{"extra_monthly":0}')),
 ('extra',public.simulate_debt_plan('{"extra_monthly":100}')),
 ('snowball',public.simulate_debt_plan('{"strategy":"snowball","extra_monthly":100}')),
 ('custom',public.simulate_debt_plan('{"strategy":"custom","custom":["e4087555-07b4-4141-95fb-d5b7ab8db92e"],"extra_monthly":100}')),
 ('lump',public.simulate_debt_plan('{"lump_sums":[{"date":"2026-12-15","amount":1000,"target_debt_id":"e4087555-07b4-4141-95fb-d5b7ab8db92e"}]}')),
 ('cash',public.simulate_debt_plan('{"lump_sums":[{"date":"2026-12-15","amount":1000,"target_debt_id":null}]}')),
 ('gone',public.simulate_debt_plan('{"payoff_now":["e4087555-07b4-4141-95fb-d5b7ab8db92e"]}')),
 ('funded',public.simulate_debt_plan('{"payoff_now":["e4087555-07b4-4141-95fb-d5b7ab8db92e"],"lump_sums":[{"date":"2026-11-13","amount":2335.59}]}')),
 ('fee',public.simulate_debt_plan('{"drop_payment":[{"label":"SoFi $10 fee","from_month":"2027-01"}]}')),
 ('bill',public.simulate_debt_plan('{"drop_payment":[{"label":"Test subscription","from_month":"2027-01"}]}')),
 ('drop',public.simulate_debt_plan('{"drop_payment":[{"debt_id":"156dff81-4895-47c1-a0e6-38c3a8fd351a","from_month":"2027-01"}]}')),
 ('raise',public.simulate_debt_plan('{"raise":{"effective_date":"2027-01-15","extra_net_per_paycheck":100}}')),
 ('ot',public.simulate_debt_plan('{"overtime":[{"pay_date":"2026-12-15","hours":10}]}')),
 ('apr',public.simulate_debt_plan('{"apr_overrides":{"e4087555-07b4-4141-95fb-d5b7ab8db92e":0}}'));

create function pg_temp.summary(p_label text,p_key text) returns text language sql as
$$ select result->'summary'->>p_key from results where label=p_label $$;
create function pg_temp.payment(p_label text,p_id text,p_month text,p_key text default 'payment') returns numeric language sql as
$$ select (x->>p_key)::numeric from results,jsonb_array_elements(result->'schedule') x
where label=p_label and x->>'debt_id'=p_id and x->>'month'=p_month $$;
select is(pg_temp.summary('default','debt_free_month'),'2029-10','corrected default payoff');
select is(pg_temp.summary('default','total_interest')::numeric,10829.44::numeric,'corrected interest includes amortized Affirm');
select is(pg_temp.summary('default','total_fees')::numeric,240::numeric,'SoFi fees reported separately');
select is((select result->'schedule' from results where label='zero'),(select result->'schedule' from results where label='minimum'),'explicit zero equals independent minimums-only schedule');
select is(pg_temp.summary('zero','interest_saved_vs_minimums')::numeric,0::numeric,'zero saves no interest against minimums');
select is(pg_temp.summary('zero','months_earlier_than_minimums')::int,0,'zero saves no months');
select is(pg_temp.payment('default','5aa25395-3701-4611-a20d-36c31ecd1777','2026-11','start'),380::numeric,'latest same-day LoveSac balance is 380');
select is(pg_temp.payment('default','5aa25395-3701-4611-a20d-36c31ecd1777','2026-11'),105::numeric,'November LoveSac retry preserved');
select is(pg_temp.payment('default','156dff81-4895-47c1-a0e6-38c3a8fd351a','2026-12'),195.75::numeric,'December Ally extension preserved');
select is((select sum((x->>'interest')::numeric) from results,jsonb_array_elements(result->'schedule') x where label='default' and x->>'month'='2026-11'),0::numeric,'November has no interest');
select ok(pg_temp.summary('extra','total_interest')::numeric < pg_temp.summary('default','total_interest')::numeric,'extra saves interest');
select ok(pg_temp.summary('extra','debt_free_month') < pg_temp.summary('default','debt_free_month'),'extra accelerates payoff');
select is(pg_temp.payment('extra','4ff8d14d-7c85-49bb-9e71-38f1e39ebb8f','2026-11'),46.63::numeric,'avalanche targets highest APR Affirm first (stable UUID tie break)');
select is(pg_temp.payment('snowball','26c2c2cf-e73d-4553-8c17-033163fe5227','2026-11'),30.30::numeric,'snowball pays smallest interest-bearing balance first');
select is(pg_temp.payment('custom','e4087555-07b4-4141-95fb-d5b7ab8db92e','2026-11'),139.13::numeric,'custom order directs 100 to GoodLeap');
select is(pg_temp.payment('lump','e4087555-07b4-4141-95fb-d5b7ab8db92e','2026-12'),1039.13::numeric,'targeted lump applied once');
select is(pg_temp.payment('lump','e4087555-07b4-4141-95fb-d5b7ab8db92e','2026-11'),39.13::numeric,'future lump does not arrive early');
select ok(pg_temp.summary('cash','total_interest')::numeric < pg_temp.summary('default','total_interest')::numeric,'untargeted lump follows strategy');
select is(pg_temp.summary('gone','what_if_removed')::numeric,2335.59::numeric,'unfunded payoff flagged as what-if');
select is(pg_temp.summary('funded','what_if_removed')::numeric,0::numeric,'lump funds immediate payoff without fictional cash');
select is(pg_temp.payment('funded','e4087555-07b4-4141-95fb-d5b7ab8db92e','2026-11'),2335.59::numeric,'payoff_now consumes lump exactly once');
select is(public.simulate_debt_plan('{"payoff_now":["E4087555-07B4-4141-95FB-D5B7AB8DB92E"]}')->'schedule',
 (select result->'schedule' from results where label='gone'),'UUID references normalize case before JSON lookup');
select is(pg_temp.payment('fee','466ed164-273e-42ca-8a2e-fa10ebf33377','2026-12','fee'),10::numeric,'fee exists before drop month');
select is(pg_temp.payment('fee','466ed164-273e-42ca-8a2e-fa10ebf33377','2027-01','fee'),0::numeric,'fee removed on effective month');
select ok(pg_temp.summary('fee','total_fees')::numeric < pg_temp.summary('default','total_fees')::numeric,'fee drop reduces fees');
select is((select sum((x->>'payment')::numeric) from results,jsonb_array_elements(result->'schedule') x where label='bill' and x->>'month'='2027-01')-
 (select sum((x->>'payment')::numeric) from results,jsonb_array_elements(result->'schedule') x where label='default' and x->>'month'='2027-01'),25::numeric,'dropped standalone bill redirects its monthly amount');
select is(pg_temp.payment('drop','156dff81-4895-47c1-a0e6-38c3a8fd351a','2027-01','minimum'),0::numeric,'debt drop stops minimum without erasing balance');
select is((select sum((x->>'payment')::numeric) from results,jsonb_array_elements(result->'schedule') x where label='raise' and x->>'month'='2027-01')-
 (select sum((x->>'payment')::numeric) from results,jsonb_array_elements(result->'schedule') x where label='default' and x->>'month'='2027-01'),100::numeric,'raise counts only paycheck after Jan 15');
select is((select sum((x->>'payment')::numeric) from results,jsonb_array_elements(result->'schedule') x where label='ot' and x->>'month'='2026-12')-
 (select sum((x->>'payment')::numeric) from results,jsonb_array_elements(result->'schedule') x where label='default' and x->>'month'='2026-12'),268::numeric,'overtime uses app_settings.extra_hour_net');
select is(pg_temp.payment('apr','e4087555-07b4-4141-95fb-d5b7ab8db92e','2026-12','interest'),0::numeric,'APR override changes interest');
select is((select jsonb_array_length(result#>'{summary,affirm_principals}') from results where label='default'),9,'every Affirm principal reported');
select ok(not exists(select 1 from results,jsonb_array_elements(result->'schedule') x join public.debts d on d.id=(x->>'debt_id')::uuid
 where label='minimum' and d.name ilike 'Affirm%' and (x->>'payment')::numeric>d.min_payment),'Affirm minimums suffice without extra');
select ok(not exists(select 1 from results r,jsonb_array_elements(r.result#>'{summary,affirm_principals}') a
 where r.label='minimum' and (select count(*) from jsonb_array_elements(r.result->'schedule') x
   where x->>'debt_id'=a->>'debt_id' and (x->>'payment')::numeric>0)>(a->>'payments_remaining')::int),
 'Affirm amortizes within its remaining installment count');
select ok((select sum((x->>'interest')::numeric) from results,jsonb_array_elements(result->'schedule') x
 join public.debts d on d.id=(x->>'debt_id')::uuid where label='extra' and d.name ilike 'Affirm%') <
 (select sum((x->>'interest')::numeric) from results,jsonb_array_elements(result->'schedule') x
 join public.debts d on d.id=(x->>'debt_id')::uuid where label='minimum' and d.name ilike 'Affirm%'),
 'extra payments save Affirm interest');
select ok(not exists(select 1 from results,jsonb_array_elements(result->'schedule') x join public.debts d on d.id=(x->>'debt_id')::uuid
 where label='extra' and d.apr=0 and (x->>'payment')::numeric>d.min_payment),'0 percent debts stay on minimums');
select ok(not exists(select 1 from results,jsonb_array_elements(result->'schedule') x where
 (x->>'start')::numeric+(x->>'interest')::numeric+(x->>'fee')::numeric-(x->>'payment')::numeric-(x->>'what_if_removed')::numeric<>(x->>'end')::numeric
 or (x->>'end')::numeric<0),'all scenarios conserve money and have nonnegative balances');
-- Rollover is month-after-payoff: Whatnot frees 15.83 in January, not December.
select is((select sum((x->>'payment')::numeric-(x->>'minimum')::numeric) from results,jsonb_array_elements(result->'schedule') x where label='default' and x->>'month'='2026-12'),0::numeric,'no same-month rollover');
select is((select sum((x->>'payment')::numeric-(x->>'minimum')::numeric) from results,jsonb_array_elements(result->'schedule') x where label='default' and x->>'month'='2027-01'),15.83::numeric,'freed minimum rolls over next month');
-- Invalid input, ownership, function properties and write isolation.
select throws_ok($$select public.simulate_debt_plan('{"strategy":"bogus"}')$$,'P0001','Unknown strategy','invalid strategy rejected');
select throws_ok($$select public.simulate_debt_plan('{"extra_monthly":-1}')$$,'P0001','Invalid extra_monthly','negative extra rejected');
select throws_ok($$select public.simulate_debt_plan('{"strategy":"custom"}')$$,'P0001','Custom strategy requires custom debt IDs','custom needs order');
select throws_ok($$select public.simulate_debt_plan('{"payoff_now":["00000000-0000-0000-0000-000000000000"]}')$$,'P0001','Unknown active debt: 00000000-0000-0000-0000-000000000000','unknown debt rejected');
select throws_ok($$select public.simulate_debt_plan('{"lump_sums":[{"date":"2026-12-01","amount":-1}]}')$$,'P0001','Invalid lump sum','negative lump rejected');
select throws_ok($$select public.simulate_debt_plan('{"overtime":[{"pay_date":"2026-12-01","hours":-1}]}')$$,'P0001','Invalid overtime','negative hours rejected');
select throws_ok($$select public.simulate_debt_plan('{"raise":{"effective_date":"2027-01-01","extra_net_per_paycheck":-1}}')$$,'P0001','Invalid raise','negative raise rejected');
select throws_ok($$select public.simulate_debt_plan('{"apr_overrides":{"e4087555-07b4-4141-95fb-d5b7ab8db92e":-1}}')$$,'P0001','Invalid APR','negative APR rejected');
select throws_ok($$select public.simulate_debt_plan('{"apr_overrides":{"e4087555-07b4-4141-95fb-d5b7ab8db92e":null}}')$$,'P0001','APR overrides must be numbers','null APR is not silently ignored');
select throws_ok($$select public.simulate_debt_plan('{"drop_payment":[{"label":"missing","from_month":"2027-01"}]}')$$,'P0001','Label must identify one active monthly standalone bill','unknown payment rejected');
select throws_ok($$select public.simulate_debt_plan('{"lump_sums":{}}')$$,'P0001','lump_sums must be an array','bad shape rejected');
select throws_ok($$select public.simulate_debt_plan('{"exrta_monthly":100}')$$,'P0001','Unknown parameter: exrta_monthly','typo rejected');
update public.bills set frequency='biweekly',anchor_date='2026-11-13' where debt_id='26c2c2cf-e73d-4553-8c17-033163fe5227';
select throws_ok($$select public.simulate_debt_plan()$$,'P0001','Affirm payment frequency must be confirmed monthly: Affirm – Whatnot','never silently assumes Affirm frequency');
update public.bills set frequency='monthly',anchor_date=null where debt_id='26c2c2cf-e73d-4553-8c17-033163fe5227';
select is((select provolatile::text from pg_proc where oid='public.simulate_debt_plan(jsonb)'::regprocedure),'s','RPC declared STABLE');
select ok(not has_function_privilege('anon','public.simulate_debt_plan(jsonb)','execute'),'anonymous role cannot execute');
select ok(not has_function_privilege('authenticated','public._simulate_debt_schedule(jsonb,jsonb,jsonb,boolean)','execute'),'private engine not accessible to browser');
create temp table before_state as select
 (select jsonb_agg(to_jsonb(t) order by id) from public.debts t) debts,
 (select jsonb_agg(to_jsonb(t) order by id) from public.debt_balances t) balances,
 (select jsonb_agg(to_jsonb(t) order by id) from public.debt_plans t) plans,
 (select jsonb_agg(to_jsonb(t) order by id) from public.app_settings t) settings;
set local role authenticated;
select lives_ok($$select public.simulate_debt_plan('{"extra_monthly":100}')$$,'authenticated owner may simulate');
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',true);
select throws_ok($$select public.simulate_debt_plan()$$,'42501','Not signed in as the Money Hub owner','other user denied');
select set_config('request.jwt.claim.sub','',true);
select throws_ok($$select public.simulate_debt_plan()$$,'42501','Not signed in as the Money Hub owner','missing JWT denied');
reset role;
select ok((select debts=(select jsonb_agg(to_jsonb(t) order by id) from public.debts t)
 and balances=(select jsonb_agg(to_jsonb(t) order by id) from public.debt_balances t)
 and plans=(select jsonb_agg(to_jsonb(t) order by id) from public.debt_plans t)
 and settings=(select jsonb_agg(to_jsonb(t) order by id) from public.app_settings t) from before_state),'simulation leaves all source data unchanged');
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
set local transaction_read_only=on;
select lives_ok($$select public.simulate_debt_plan()$$,'RPC runs inside a READ ONLY transaction');
select * from finish();
rollback;
