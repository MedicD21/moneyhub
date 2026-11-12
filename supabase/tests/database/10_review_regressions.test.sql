-- Regression tests for defects found in independent review (each failed before the fix).
begin;
create extension if not exists pgtap with schema extensions;
-- Start from empty tables (rolled back with the test), so the suite also runs on a seeded DB.
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans cascade;
select plan(18);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-08';
insert into public.accounts (id, name, kind, balance_includes_pending) values
  ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking', false),
  ('a0000000-0000-0000-0000-000000000002', 'Card',     'credit_card', false),
  ('a0000000-0000-0000-0000-000000000003', 'CU',       'checking', true);

-- R1: commit without a balance on a fresh session must not fail
select lives_ok(
  $$select public.commit_screenshot_import('a0000000-0000-0000-0000-000000000001',
      '[{"txn_date":"2026-03-06","description_raw":"KROGER","amount":-20}]'::jsonb)$$,
  'R1 commit_screenshot_import works without p_balance');
select is((select count(*)::int from public.transactions where description_raw = 'KROGER'), 1, 'R1 row inserted');

-- R2: pending row that posts with its original date (bank excludes pending)
insert into public.balance_snapshots (account_id, as_of_date, balance, created_at) values
  ('a0000000-0000-0000-0000-000000000002', '2026-03-05', 0, now() - interval '2 hours');
insert into public.balance_snapshots (id, account_id, as_of_date, balance, created_at) values
  ('50000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '2026-03-05', 1000, now() - interval '2 hours');
insert into public.transactions (id, account_id, txn_date, description_raw, amount, status, created_at) values
  ('70000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '2026-03-04', 'SQ *CAFE', -50, 'pending', now() - interval '3 hours');
select is((select estimated_balance from public.v_account_balances where account_id = 'a0000000-0000-0000-0000-000000000001'),
          930.00::numeric, 'R2 pending row lowers the estimate (1000 - 20 - 50)');
update public.transactions set status = 'posted' where id = '70000000-0000-0000-0000-000000000001';
select is((select estimated_balance from public.v_account_balances where account_id = 'a0000000-0000-0000-0000-000000000001'),
          930.00::numeric, 'R2 estimate unchanged when it posts with its original (pre-snapshot) date');
select ok((select posted_at is not null and pending_txn_date = '2026-03-04' from public.transactions
            where id = '70000000-0000-0000-0000-000000000001'), 'R2 posting is recorded');
insert into public.balance_snapshots (id, account_id, as_of_date, balance) values
  ('50000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', '2026-03-08', 930);
select is((select difference from public.v_balance_check where snapshot_id = '50000000-0000-0000-0000-000000000002'),
          0::numeric, 'R2 next snapshot reconciles (no false "missing row")');

-- R2b: bank includes pending; pending dated 03-04 posts dated 03-06
insert into public.balance_snapshots (account_id, as_of_date, balance, created_at) values
  ('a0000000-0000-0000-0000-000000000003', '2026-03-05', 950, now() - interval '2 hours');
insert into public.transactions (id, account_id, txn_date, description_raw, amount, status, created_at) values
  ('70000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000003', '2026-03-04', 'GAS', -50, 'pending', now() - interval '3 hours');
update public.transactions set status = 'posted', txn_date = '2026-03-06' where id = '70000000-0000-0000-0000-000000000002';
select is((select estimated_balance from public.v_account_balances where account_id = 'a0000000-0000-0000-0000-000000000003'),
          950.00::numeric, 'R2b includes-pending bank: a posted row already in the balance is not subtracted twice');

-- R2c: row dated on the snapshot day but recorded after the snapshot
insert into public.transactions (account_id, txn_date, description_raw, amount) values
  ('a0000000-0000-0000-0000-000000000002', '2026-03-05', 'LATE SAME-DAY', -30);
select is((select estimated_balance_display from public.v_account_balances where account_id = 'a0000000-0000-0000-0000-000000000002'),
          30.00::numeric, 'R2c same-day row recorded after the snapshot counts toward the estimate');

-- R3: update path honours debt_id / tags / needs_review
insert into public.debts (id, name, kind, apr, min_payment, due_day) values
  ('d0000000-0000-0000-0000-000000000001', 'Auto', 'auto', 6.9, 200, 10);
insert into public.income_sources (name, frequency, anchor_date, expected_net) values ('Job', 'biweekly', '2026-03-06', 2000);
insert into public.transactions (account_id, txn_date, description_raw, amount, status, needs_review, review_question) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-06', 'AUTO LOAN PMT', -200, 'pending', true, 'Which category is this?');
select public.commit_screenshot_import('a0000000-0000-0000-0000-000000000001',
  '[{"txn_date":"2026-03-07","description_raw":"AUTO LOAN PMT","amount":-200,"category":"Debt Payment",
     "debt_id":"d0000000-0000-0000-0000-000000000001","tags":["car"]}]'::jsonb);
select results_eq(
  $$select status, debt_id, tags, needs_review from public.transactions where description_raw = 'AUTO LOAN PMT'$$,
  $$values ('posted'::text, 'd0000000-0000-0000-0000-000000000001'::uuid, '{car}'::text[], false)$$,
  'R3 pending->posted update applies debt_id, tags and clears the category review');
select is((select minimums_total from public.paycheck_plan()), 0::numeric,
          'R3 the linked payment satisfies the debt minimum');

-- R4: due_day 31 — a March 31 payment does not satisfy April's minimum
update public.debts set due_day = 31 where id = 'd0000000-0000-0000-0000-000000000001';
update public.income_sources set frequency = 'monthly', anchor_date = '2026-04-30';
insert into public.transactions (account_id, txn_date, description_raw, amount, debt_id) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-31', 'AUTO 0331', -200, 'd0000000-0000-0000-0000-000000000001');
select is((select minimums_total from public.paycheck_plan('2026-04-30')), 200::numeric,
          'R4 minimum-paid window is (previous due date, due date]');

-- R5: partial payments recompute from all linked transactions
insert into public.bills (id, name, amount, frequency, due_day) values ('e0000000-0000-0000-0000-000000000001', 'Water', 100, 'monthly', 20);
select public.ensure_bill_occurrences('2026-03-31');
insert into public.import_batches (id, account_id) values
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001'),
  ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001');
insert into public.transactions (id, account_id, import_batch_id, txn_date, description_raw, amount) values
  ('70000000-0000-0000-0000-000000000011', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', '2026-03-10', 'WATER 1', -50),
  ('70000000-0000-0000-0000-000000000012', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', '2026-03-15', 'WATER 2', -50);
create temp table occ as select id from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000001';
select public.mark_bill_paid((select id from occ), '70000000-0000-0000-0000-000000000011');
select public.mark_bill_paid((select id from occ), '70000000-0000-0000-0000-000000000012');
select public.mark_bill_paid((select id from occ), '70000000-0000-0000-0000-000000000011');
select results_eq($$select status, paid_amount from public.bill_occurrences where id = (select id from occ)$$,
                  $$values ('paid'::text, 100.00::numeric)$$, 'R5 two partial payments add up; re-marking is idempotent');
delete from public.import_batches where id = 'b0000000-0000-0000-0000-000000000002';
select results_eq($$select status, paid_amount, paid_date from public.bill_occurrences where id = (select id from occ)$$,
                  $$values ('partial'::text, 50.00::numeric, '2026-03-10'::date)$$, 'R5 undoing one payment leaves partial 50');
delete from public.import_batches where id = 'b0000000-0000-0000-0000-000000000001';
select results_eq($$select status, paid_amount from public.bill_occurrences where id = (select id from occ)$$,
                  $$values ('due'::text, null::numeric)$$, 'R5 undoing both payments returns it to due');

-- R6: changing a bill's due day replaces future unpaid occurrences
insert into public.bills (id, name, amount, frequency, due_day) values ('e0000000-0000-0000-0000-000000000002', 'Gym', 80, 'monthly', 20);
select public.ensure_bill_occurrences('2026-04-30');
update public.bills set due_day = 25 where id = 'e0000000-0000-0000-0000-000000000002';
select results_eq(
  $$select due_date from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000002' order by 1$$,
  $$values ('2026-03-25'::date), ('2026-04-25')$$, 'R6 no stale occurrences on the old due day');

-- R7: pending->posted update whose new fingerprint already exists gets occurrence 2
insert into public.transactions (account_id, txn_date, description_raw, amount, status) values
  ('a0000000-0000-0000-0000-000000000002', '2026-03-05', 'STARBUCKS', -5, 'posted'),
  ('a0000000-0000-0000-0000-000000000002', '2026-03-05', 'STARBUCKS #123', -5, 'pending');
select lives_ok(
  $$select public.commit_screenshot_import('a0000000-0000-0000-0000-000000000002',
      '[{"txn_date":"2026-03-05","description_raw":"STARBUCKS","amount":-5,"category":"Dining"},
        {"txn_date":"2026-03-05","description_raw":"STARBUCKS","amount":-5,"category":"Dining"}]'::jsonb)$$,
  'R7 commit succeeds');
select results_eq(
  $$select occurrence, status from public.transactions where account_id = 'a0000000-0000-0000-0000-000000000002'
     and description_raw = 'STARBUCKS' order by occurrence$$,
  $$values (1, 'posted'::text), (2, 'posted')$$, 'R7 updated row takes occurrence 2');

-- R8: an 'ask' row resolved as insert reserves its occurrence number
insert into public.transactions (account_id, txn_date, description_raw, amount) values
  ('a0000000-0000-0000-0000-000000000003', '2026-03-07', 'COFFEE A', -5);
select lives_ok(
  $$select public.commit_screenshot_import('a0000000-0000-0000-0000-000000000003',
      '[{"txn_date":"2026-03-07","description_raw":"COFFEE B","amount":-5,"resolution":"insert","category":"Dining"},
        {"txn_date":"2026-03-07","description_raw":"COFFEE A","amount":-5},
        {"txn_date":"2026-03-07","description_raw":"COFFEE B","amount":-5,"category":"Dining"}]'::jsonb)$$,
  'R8 resolved ask + identical insert do not collide');

select * from finish();
rollback;
