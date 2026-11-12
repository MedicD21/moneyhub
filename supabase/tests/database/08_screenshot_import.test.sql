-- Phase 2 acceptance, proven in SQL against the procedures Claude calls:
--   * two overlapping screenshots in a row -> zero duplicates
--   * pending -> posted updates the existing row instead of inserting
--   * balance check reports 0
-- plus near-match handling, merchant rules, category guard, bill matching, undo.
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-08';

insert into public.accounts (id, name, kind) values ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking');
insert into public.merchant_rules (pattern, merchant, category_id) values
  ('kroger', 'Kroger', (select id from public.categories where name = 'Groceries')),
  ('NETFLIX', 'Netflix', (select id from public.categories where name = 'Subscriptions'));
insert into public.bills (id, name, amount, frequency, due_day, match_pattern) values
  ('e0000000-0000-0000-0000-000000000001', 'Netflix', 15.49, 'monthly', 5, 'NETFLIX');
select public.ensure_bill_occurrences('2026-03-31');

-- ---------------- Screenshot 1: Mar 1 - Mar 5 ----------------
create temp table shot1 as select $j$[
  {"txn_date":"2026-03-01","description_raw":"PAYROLL ACME","amount":2000.00,"category":"Income"},
  {"txn_date":"2026-03-02","description_raw":"KROGER #123","amount":-45.10},
  {"txn_date":"2026-03-03","description_raw":"STARBUCKS","amount":-5.00},
  {"txn_date":"2026-03-03","description_raw":"STARBUCKS","amount":-5.00},
  {"txn_date":"2026-03-04","description_raw":"NETFLIX.COM","amount":-15.49},
  {"txn_date":"2026-03-05","description_raw":"SQ *JOES COFFEE","amount":-12.00,"status":"pending"}
]$j$::jsonb as rows;

select results_eq(
  $$select action, insert_occurrence from public.preview_screenshot_import(
      'a0000000-0000-0000-0000-000000000001', (select rows from shot1)) order by row_num$$,
  $$values ('insert'::text, 1), ('insert', 1), ('insert', 1), ('insert', 2), ('insert', 1), ('insert', 1)$$,
  'screenshot 1 preview: all new; the identical second Starbucks gets occurrence 2');
select is(
  (select suggested_category from public.preview_screenshot_import(
     'a0000000-0000-0000-0000-000000000001', (select rows from shot1)) where row_num = 2),
  'Groceries', 'preview suggests the merchant rule category');
select is((select count(*)::int from public.transactions), 0, 'preview writes nothing');

create temp table r1 as select public.commit_screenshot_import(
  'a0000000-0000-0000-0000-000000000001', (select rows from shot1),
  p_balance => 1929.41, p_as_of_date => '2026-03-05') as res;

select results_eq(
  $$select (res->>'inserted')::int, (res->>'updated')::int, (res->>'skipped')::int from r1$$,
  $$values (6, 0, 0)$$, 'screenshot 1 commit inserts 6');
select is((select res->'balance_check'->>'note' from r1),
          'first snapshot for this account; nothing to compare', 'first snapshot has no balance check');
select results_eq(
  $$select merchant, c.name from public.transactions t join public.categories c on c.id = t.category_id
     where description_raw = 'KROGER #123'$$,
  $$values ('Kroger'::text, 'Groceries'::text)$$, 'merchant rule applied on insert');
select results_eq(
  $$select needs_review, review_question from public.transactions where description_raw = 'STARBUCKS' and occurrence = 1$$,
  $$values (true, 'Which category is this?'::text)$$, 'uncategorized rows are queued for review');
select is((select rows_inserted from public.import_batches where id = (select (res->>'import_batch_id')::uuid from r1)),
          6, 'batch counts are recorded');
select is((select (res->>'bill_match_candidates')::int from r1), 1, 'Netflix payment is offered as a bill match');

-- Bill matching (Claude confirms, then marks paid)
select public.mark_bill_paid(m.occurrence_id, m.transaction_id)
  from public.v_bill_match_candidates m where m.rank = 1;
select results_eq(
  $$select status, paid_amount, paid_date from public.bill_occurrences where due_date = '2026-03-05'$$,
  $$values ('paid'::text, 15.49::numeric, '2026-03-04'::date)$$, 'bill occurrence marked paid and linked');
select is((select count(*)::int from public.v_bill_match_candidates), 0, 'a matched payment is no longer a candidate');

-- ---------------- Screenshot 2: Mar 3 - Mar 8 (overlaps) ----------------
create temp table shot2 as select $j$[
  {"txn_date":"2026-03-03","description_raw":"STARBUCKS","amount":-5.00},
  {"txn_date":"2026-03-03","description_raw":"STARBUCKS","amount":-5.00},
  {"txn_date":"2026-03-04","description_raw":"NETFLIX.COM","amount":-15.49},
  {"txn_date":"2026-03-06","description_raw":"SQ *JOES COFFEE SHOP","amount":-12.00},
  {"txn_date":"2026-03-07","description_raw":"SHELL OIL 5551","amount":-40.00,"category":"Gas"},
  {"txn_date":"2026-03-08","description_raw":"AMAZON MKTPLACE","amount":-12.00,"category":"Shopping"}
]$j$::jsonb as rows;

select results_eq(
  $$select action from public.preview_screenshot_import(
      'a0000000-0000-0000-0000-000000000001', (select rows from shot2)) order by row_num$$,
  $$values ('skip'::text), ('skip'), ('skip'), ('update'), ('insert'), ('insert')$$,
  'screenshot 2 preview: overlap skipped, pending->posted update, 2 new');

create temp table pending_id as
  select id from public.transactions where description_raw = 'SQ *JOES COFFEE';
create temp table r2 as select public.commit_screenshot_import(
  'a0000000-0000-0000-0000-000000000001', (select rows from shot2),
  p_balance => 1865.41, p_as_of_date => '2026-03-08') as res;

select results_eq(
  $$select (res->>'inserted')::int, (res->>'updated')::int, (res->>'skipped')::int from r2$$,
  $$values (2, 1, 3)$$, 'screenshot 2 commit: 2 inserted, 1 updated, 3 skipped');
select is((select count(*)::int from public.transactions), 8, 'zero duplicates after two overlapping screenshots');
select is((select count(*)::int from public.transactions where description_raw = 'STARBUCKS'), 2,
          'identical same-day transactions are kept as two rows, not four');
select results_eq(
  $$select id, status, txn_date, description_raw from public.transactions where amount = -12.00 and status = 'posted'
     and description_raw like 'SQ%'$$,
  $$select id, 'posted'::text, '2026-03-06'::date, 'SQ *JOES COFFEE SHOP'::text from pending_id$$,
  'pending -> posted updated the same row (same id, new date and description)');
select is((select (res->'balance_check'->>'difference')::numeric from r2), 0::numeric,
          'balance check after screenshot 2 reports 0');
select is((select difference from public.v_balance_check where is_latest), 0::numeric,
          'v_balance_check agrees: difference 0');

-- ---------------- Screenshot 3: near-match must be asked ----------------
create temp table shot3 as select $j$[
  {"txn_date":"2026-03-07","description_raw":"SHELL SERVICE STATION","amount":-40.00}
]$j$::jsonb as rows;
select is(
  (select action from public.preview_screenshot_import('a0000000-0000-0000-0000-000000000001', (select rows from shot3))),
  'ask', 'same amount within 3 days but different text -> ask');
select throws_like(
  $$select public.commit_screenshot_import('a0000000-0000-0000-0000-000000000001', (select rows from shot3))$$,
  'Unresolved near-matches%', 'commit refuses unresolved near-matches');
select is(
  (select (public.commit_screenshot_import('a0000000-0000-0000-0000-000000000001',
     '[{"txn_date":"2026-03-07","description_raw":"SHELL SERVICE STATION","amount":-40.00,"resolution":"skip"}]'::jsonb)
   ->>'skipped')::int),
  1, 'resolution "skip" leaves it out');
select is(
  (select (public.commit_screenshot_import('a0000000-0000-0000-0000-000000000001',
     '[{"txn_date":"2026-03-07","description_raw":"SHELL SERVICE STATION","amount":-40.00,"resolution":"insert","category":"Gas"}]'::jsonb)
   ->>'inserted')::int),
  1, 'resolution "insert" adds it as a separate transaction');

-- Category guard
select throws_like(
  $$select public.commit_screenshot_import('a0000000-0000-0000-0000-000000000001',
      '[{"txn_date":"2026-03-08","description_raw":"NEW PLACE","amount":-1.00,"category":"Crypto"}]'::jsonb)$$,
  'Unknown category "Crypto"%', 'unknown category names are rejected (never invented)');

-- Bad input
select throws_like(
  $$select * from public.preview_screenshot_import('a0000000-0000-0000-0000-000000000001',
      '[{"txn_date":"2026-03-08","amount":-1.00}]'::jsonb)$$,
  'Row 1 is missing%', 'rows missing required fields are rejected');

-- Undo screenshot 2
delete from public.import_batches where id = (select (res->>'import_batch_id')::uuid from r2);
select is((select count(*)::int from public.transactions where description_raw in ('SHELL OIL 5551','AMAZON MKTPLACE')),
          0, 'deleting batch 2 removes the rows it inserted');
select is((select count(*)::int from public.balance_snapshots), 1, 'and its balance snapshot');

select * from finish();
rollback;
