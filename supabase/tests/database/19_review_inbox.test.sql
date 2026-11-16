-- Review inbox: review_transaction and create_merchant_rule (migration 20261115000000_review_inbox.sql).
--
-- Today is 2026-03-10. One checking account. Water bill (monthly, day 20) has March and April occurrences.
-- Visa has a payment bill (day 12). Imported rows:
--   ...01 KROGER #1   -40     posted   flagged, note from Claude
--   ...02 KROGER #2   -10     pending  flagged, no category
--   ...03 KROGER REFUND +50   posted
--   ...04 HOME CHEF   -130.83 posted   flagged, reconciled by Claude
--   ...05 KROGER #3   -7      posted   flagged but already categorized (Dining)
-- Sections:
--   1. review_transaction on an imported row, on a reconciled row, and keeping the flag
--   2. validation (category/sign, bill/debt sign, bill vs debt, unknown ids, note)
--   3. bill link on, moved, off (both occurrences recalculate); debt-only link auto-links
--   4. locked columns never move; direct table writes from a web session still fail
--   5. owner check and privileges
--   6. create_merchant_rule; new imports use the rule
begin;
create extension if not exists pgtap with schema extensions;
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans, public.envelopes cascade;
grant execute on all functions in schema extensions to anon, authenticated;
select plan(59);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'owner@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'someone@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-10';

insert into public.accounts (id, name, kind) values ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking');
insert into public.balance_snapshots (account_id, as_of_date, balance) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-01', 1000);
insert into public.debts (id, name, kind, apr, min_payment) values
  ('d0000000-0000-0000-0000-000000000001', 'Visa', 'credit_card', 24.99, 35);
insert into public.bills (id, name, amount, frequency, due_day) values
  ('e0000000-0000-0000-0000-000000000001', 'Water', 100, 'monthly', 20);
insert into public.bills (id, name, amount, frequency, due_day, debt_id) values
  ('e0000000-0000-0000-0000-000000000002', 'Visa payment', 35, 'monthly', 12, 'd0000000-0000-0000-0000-000000000001');
select public.ensure_bill_occurrences('2026-04-30');
-- A category owned by someone else (only possible by writing as the table owner).
insert into public.categories (id, owner_id, name, kind) values
  ('c0000000-0000-0000-0000-00000000beef', '22222222-2222-2222-2222-222222222222', 'Not yours', 'expense');
insert into public.set_asides (id, name, per_paycheck, start_date) values
  ('5a000000-0000-0000-0000-000000000001', 'Car', 50, '2026-03-06');

insert into public.transactions (id, account_id, txn_date, description_raw, merchant, amount, status, needs_review, review_question, note, category_id, set_aside_id) values
  ('77000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '2026-03-05', 'KROGER #1', 'Kroger', -40, 'posted', true, 'Which category is this?', 'from Claude', null, '5a000000-0000-0000-0000-000000000001'),
  ('77000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', '2026-03-06', 'KROGER #2', 'Kroger', -10, 'pending', true, 'Which category is this?', null, null, null),
  ('77000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', '2026-03-07', 'KROGER REFUND', 'Kroger', 50, 'posted', false, null, null, null, null),
  ('77000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', '2026-03-08', 'HOME CHEF', 'Home Chef', -130.83, 'posted', true, 'Which category is this?', null, null, null),
  ('77000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', '2026-03-09', 'KROGER #3', 'Kroger', -7, 'posted', true, 'Gas or food?', null,
     (select id from public.categories where name = 'Dining' and owner_id = '11111111-1111-1111-1111-111111111111'), null);
select public.reconcile_transactions(array['77000000-0000-0000-0000-000000000004'::uuid]);

-- Snapshot of every column review_transaction must never touch.
create temp table locked as
select id, amount, txn_date, description_raw, merchant, status, cleared, reconciled, reconciled_at, occurrence,
       fingerprint, set_aside_id, account_id, entry_source
from public.transactions;
create temp table occ as
select o.id, o.due_date from public.bill_occurrences o where o.bill_id = 'e0000000-0000-0000-0000-000000000001';
grant select on locked, occ to authenticated;

-- ============ 1. review_transaction ============
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select lives_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000001',
      (select id from public.categories where name = 'Groceries'), '  weekly shop ', null, null)$$,
  'review: an imported row can be classified');
select results_eq(
  $$select category_name, note, needs_review, review_question is null
      from public.v_transactions where id = '77000000-0000-0000-0000-000000000001'$$,
  $$values ('Groceries'::text, 'weekly shop'::text, false, true)$$,
  'review: category and trimmed note set, flag and question cleared');

select lives_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000004',
      (select id from public.categories where name = 'Groceries'), 'meal kit', null, null)$$,
  'review: a reconciled row can be classified');
select results_eq(
  $$select category_name, note, needs_review, reconciled from public.v_transactions
     where id = '77000000-0000-0000-0000-000000000004'$$,
  $$values ('Groceries'::text, 'meal kit'::text, false, true)$$,
  'review: the reconciled row is classified and stays reconciled');

select lives_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000002', null, 'ask Claude', null, null, false)$$,
  'review: p_resolve = false saves without resolving');
select results_eq(
  $$select needs_review, review_question, note from public.transactions where id = '77000000-0000-0000-0000-000000000002'$$,
  $$values (true, 'Which category is this?'::text, 'ask Claude'::text)$$,
  'review: p_resolve = false keeps the flag and the question');

-- ============ 2. validation ============
select throws_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000002',
      (select id from public.categories where name = 'Income'), null, null, null)$$,
  'P0001', 'An income category needs money coming in', 'review: an income category on money out is rejected');
select lives_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000003',
      (select id from public.categories where name = 'Income'), null, null, null)$$,
  'review: an income category on money in is accepted');
select throws_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000003', null, null,
      (select id from occ order by due_date limit 1), null)$$,
  'P0001', 'A bill payment must be money going out', 'review: a bill link on money in is rejected');
select throws_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000003', null, null, null,
      'd0000000-0000-0000-0000-000000000001')$$,
  'P0001', 'A debt payment must be money going out', 'review: a debt link on money in is rejected');
select throws_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000002', null, null,
      (select id from occ order by due_date limit 1), 'd0000000-0000-0000-0000-000000000001')$$,
  'P0001', 'That bill does not pay that debt', 'review: a debt that conflicts with the bill is rejected');
select throws_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000002', null, null,
      '00000000-0000-0000-0000-000000000000', null)$$,
  'P0001', 'Unknown bill', 'review: an unknown bill is rejected');
select throws_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000002', null, null, null,
      '00000000-0000-0000-0000-000000000000')$$,
  'P0001', 'Unknown debt', 'review: an unknown debt is rejected');
select throws_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-00000000beef',
      null, null, null)$$,
  'P0001', 'Unknown category', 'review: another owner''s category is rejected');
select throws_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000002', null, repeat('x', 501), null, null)$$,
  'P0001', 'The note is too long (500 characters max)', 'review: a note over 500 characters is rejected');
select throws_ok(
  $$select public.review_transaction('00000000-0000-0000-0000-000000000000', null, null, null, null)$$,
  'P0001', 'Transaction not found', 'review: an unknown transaction is rejected');

-- ============ 3. links and their triggers ============
select lives_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000001',
      (select id from public.categories where name = 'Groceries'), null, (select id from occ order by due_date limit 1), null)$$,
  'bill: link the Kroger row to the March Water occurrence');
select results_eq(
  $$select o.status, o.paid_amount from public.bill_occurrences o join occ using (id) order by occ.due_date$$,
  $$values ('partial'::text, 40::numeric), ('due'::text, null::numeric)$$,
  'bill on: March is partially paid by 40, April untouched');
select lives_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000001',
      (select id from public.categories where name = 'Groceries'), null, (select id from occ order by due_date desc limit 1), null)$$,
  'bill: move the link to April');
select results_eq(
  $$select o.status, o.paid_amount from public.bill_occurrences o join occ using (id) order by occ.due_date$$,
  $$values ('due'::text, null::numeric), ('partial'::text, 40::numeric)$$,
  'bill moved: both occurrences recalculate (March back to due, April partial)');
select lives_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000001',
      (select id from public.categories where name = 'Groceries'), null, null, null)$$,
  'bill: clear the link');
select results_eq(
  $$select o.status, o.paid_amount from public.bill_occurrences o join occ using (id) order by occ.due_date$$,
  $$values ('due'::text, null::numeric), ('due'::text, null::numeric)$$,
  'bill off: the old occurrence recalculates (April back to due)');

select lives_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000002', null, null,
      (select o.id from public.bill_occurrences o where o.bill_id = 'e0000000-0000-0000-0000-000000000002' order by o.due_date limit 1),
      null, false)$$,
  'bill: a Visa bill alone is accepted');
select is((select debt_id from public.transactions where id = '77000000-0000-0000-0000-000000000002'),
  'd0000000-0000-0000-0000-000000000001'::uuid, 'bill: the bill''s debt is filled in (link_debt_transaction)');
select lives_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000002', null, null, null, null, false)$$,
  'bill: clear both links');
select lives_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000002', null, null, null,
      'd0000000-0000-0000-0000-000000000001', false)$$,
  'debt: a debt-only link on money out is accepted');
select results_eq(
  $$select t.bill_occurrence_id = o.id, o.due_date, o.status, o.paid_amount
      from public.transactions t
      join public.bill_occurrences o on o.bill_id = 'e0000000-0000-0000-0000-000000000002' and o.due_date = '2026-03-12'
     where t.id = '77000000-0000-0000-0000-000000000002'$$,
  $$values (true, '2026-03-12'::date, 'partial'::text, 10::numeric)$$,
  'debt: link_debt_transaction auto-links the nearest open Visa occurrence and it recalculates');

-- ============ 4. locked columns and direct writes ============
select results_eq(
  $$select id, amount, txn_date, description_raw, merchant, status, cleared, reconciled, reconciled_at, occurrence,
           fingerprint, set_aside_id, account_id, entry_source
      from public.transactions order by id$$,
  $$select * from locked order by id$$,
  'locked: after every call above, amount, date, names, status, cleared, reconciliation, occurrence, fingerprint and set-aside are unchanged');

select throws_ok($$update public.transactions set amount = -41 where id = '77000000-0000-0000-0000-000000000001'$$,
  '42501', null, 'direct: a web session cannot update an imported amount');
select throws_ok($$update public.transactions set category_id = null where id = '77000000-0000-0000-0000-000000000001'$$,
  '42501', null, 'direct: a web session cannot update even a category directly');
select throws_ok($$update public.transactions set reconciled = false where id = '77000000-0000-0000-0000-000000000004'$$,
  '42501', null, 'direct: a web session cannot touch reconciled');
select throws_ok($$delete from public.transactions where id = '77000000-0000-0000-0000-000000000001'$$,
  '42501', null, 'direct: a web session cannot delete');
select throws_ok($$insert into public.merchant_rules (pattern) values ('xx')$$,
  '42501', null, 'direct: a web session cannot insert a merchant rule');

-- The guard is still authoritative: with privileges out of the way (table owner + web JWT), it still blocks.
reset role;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select throws_ok($$update public.transactions set amount = -1 where id = '77000000-0000-0000-0000-000000000004'$$,
  '42501', 'A reconciled transaction can no longer be changed', 'guard: reconciled amount stays locked');
select throws_ok($$update public.transactions set reconciled = false where id = '77000000-0000-0000-0000-000000000004'$$,
  '42501', 'Only Claude can change reconciliation', 'guard: reconciliation stays Claude-only');

-- ============ 5. owner check and privileges ============
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select throws_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000001', null, null, null, null)$$,
  '42501', 'Not signed in as the Money Hub owner', 'owner: another signed-in user cannot review');
select throws_ok(
  $$select public.create_merchant_rule('kroger', 'c0000000-0000-0000-0000-00000000beef')$$,
  '42501', 'Not signed in as the Money Hub owner', 'owner: another signed-in user cannot create a rule');
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';
select throws_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000001', null, null, null, null)$$,
  '42501', null, 'anon: cannot call review_transaction');
select throws_ok(
  $$select public.create_merchant_rule('kroger', null)$$,
  '42501', null, 'anon: cannot call create_merchant_rule');
reset role;
select ok(has_function_privilege('authenticated', 'public.review_transaction(uuid, uuid, text, uuid, uuid, boolean)', 'execute')
      and has_function_privilege('authenticated', 'public.create_merchant_rule(text, uuid, text, boolean)', 'execute'),
  'privileges: authenticated can execute both');
select ok(not has_function_privilege('anon', 'public.review_transaction(uuid, uuid, text, uuid, uuid, boolean)', 'execute')
      and not has_function_privilege('anon', 'public.create_merchant_rule(text, uuid, text, boolean)', 'execute'),
  'privileges: anon cannot execute either');
select ok(not has_function_privilege('authenticated', 'public.reconcile_transactions(uuid[])', 'execute')
      and not has_function_privilege('authenticated', 'public.unreconcile_transactions(uuid[])', 'execute'),
  'privileges: reconciliation stays Claude-only');
select ok((select prosecdef and proconfig @> array['search_path=""'] from pg_proc
            where oid = 'public.review_transaction(uuid, uuid, text, uuid, uuid, boolean)'::regprocedure),
  'review_transaction is SECURITY DEFINER with an empty search_path');
select ok((select prosecdef and proconfig @> array['search_path=""'] from pg_proc
            where oid = 'public.create_merchant_rule(text, uuid, text, boolean)'::regprocedure),
  'create_merchant_rule is SECURITY DEFINER with an empty search_path');

-- ============ 6. create_merchant_rule ============
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
-- Reopen KROGER #2 as an uncategorized review row (it got links above)
select public.review_transaction('77000000-0000-0000-0000-000000000002', null, null, null, null, false);

select throws_ok($$select public.create_merchant_rule('  k  ', (select id from public.categories where name = 'Groceries'))$$,
  'P0001', 'The pattern needs at least 2 characters', 'rule: a 1-character pattern is rejected');
select throws_ok($$select public.create_merchant_rule('kroger', null)$$,
  'P0001', 'Choose a category', 'rule: a category is required');
select throws_ok($$select public.create_merchant_rule('kroger', 'c0000000-0000-0000-0000-00000000beef')$$,
  'P0001', 'Unknown category', 'rule: another owner''s category is rejected');
select is(public.create_merchant_rule('  kroger ', (select id from public.categories where name = 'Income'), null, true), 0,
  'rule: an income rule is never applied to money out');
select throws_ok($$select public.create_merchant_rule('KROGER', (select id from public.categories where name = 'Groceries'))$$,
  'P0001', 'A rule for "KROGER" already exists', 'rule: a case-insensitive duplicate is rejected');
select is(
  public.create_merchant_rule('KROGER #', (select id from public.categories where name = 'Groceries'), ' Kroger ', true), 1,
  'rule: apply-to-open returns the count (only the open, uncategorized KROGER #2)');
select results_eq(
  $$select id, category_name, needs_review from public.v_transactions
     where id in ('77000000-0000-0000-0000-000000000002', '77000000-0000-0000-0000-000000000005') order by id$$,
  $$values ('77000000-0000-0000-0000-000000000002'::uuid, 'Groceries'::text, false),
           ('77000000-0000-0000-0000-000000000005'::uuid, 'Dining'::text, true)$$,
  'rule: the matching open row is categorized; a flagged row that already has a category is untouched');
select is((select review_question from public.transactions where id = '77000000-0000-0000-0000-000000000002'), null,
  'rule: the applied row''s question is cleared');
select results_eq(
  $$select pattern, merchant from public.merchant_rules order by length(pattern) desc$$,
  $$values ('KROGER #'::text, 'Kroger'::text), ('kroger'::text, null::text)$$,
  'rule: pattern and merchant are stored trimmed');
select is(public.create_merchant_rule('home chef', (select id from public.categories where name = 'Groceries')), 0,
  'rule: without apply-to-open the count is 0');
select is((select count(*)::int from public.transactions where needs_review), 1,
  'rule: only the already-categorized KROGER #3 is still flagged');
select results_eq(
  $$select id, amount, txn_date, description_raw, merchant, status, cleared, reconciled, occurrence
      from public.transactions order by id$$,
  $$select id, amount, txn_date, description_raw, merchant, status, cleared, reconciled, occurrence from locked order by id$$,
  'rule: applying a rule changes no amount, date, name, status, cleared or reconciliation');

-- The chat connector (no JWT) can use both functions too; new imports use the saved rules.
reset role;
set local request.jwt.claims = '';
select lives_ok(
  $$select public.review_transaction('77000000-0000-0000-0000-000000000005', null, null, null, null, false)$$,
  'chat: a direct session (no JWT) resolves the owner via app_settings');
select lives_ok(
  $$select public.commit_screenshot_import('a0000000-0000-0000-0000-000000000001',
      '[{"txn_date":"2026-03-09","description_raw":"KROGER #77","amount":-12.00}]'::jsonb)$$,
  'import: a new Kroger row is imported');
select results_eq(
  $$select category_name, needs_review from public.v_transactions where description_raw = 'KROGER #77'$$,
  $$values ('Groceries'::text, false)$$,
  'import: commit_screenshot_import applies the saved merchant rule');

select * from finish();
rollback;
