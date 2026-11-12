-- Phase 1: fingerprint uniqueness + occurrence, owner_id default
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');

insert into public.accounts (id, name, kind) values
  ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking'),
  ('a0000000-0000-0000-0000-000000000002', 'Savings',  'savings');

insert into public.transactions (id, account_id, txn_date, description_raw, amount)
values ('70000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001',
        '2026-03-01', 'KROGER #123', -45.1);

select is(
  (select fingerprint from public.transactions where id = '70000000-0000-0000-0000-000000000001'),
  'a0000000-0000-0000-0000-000000000001|2026-03-01|-45.10|kroger123',
  'fingerprint = account|ISO date|amount(2dp)|normalized description');

select is(
  (select owner_id from public.transactions where id = '70000000-0000-0000-0000-000000000001'),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'owner_id defaults to app_settings.owner_id when auth.uid() is null (Claude writes)');

select throws_ok(
  $$insert into public.transactions (account_id, txn_date, description_raw, amount)
    values ('a0000000-0000-0000-0000-000000000001', '2026-03-01', 'Kroger 123', -45.10)$$,
  '23505', null,
  'same fingerprint + same occurrence is rejected (case/punctuation-insensitive)');

select lives_ok(
  $$insert into public.transactions (account_id, txn_date, description_raw, amount, occurrence)
    values ('a0000000-0000-0000-0000-000000000001', '2026-03-01', 'KROGER #123', -45.10, 2)$$,
  'occurrence = 2 for a second identical transaction succeeds');

select throws_ok(
  $$insert into public.transactions (account_id, txn_date, description_raw, amount, occurrence)
    values ('a0000000-0000-0000-0000-000000000001', '2026-03-01', 'KROGER #123', -45.10, 2)$$,
  '23505', null,
  'a duplicate occurrence = 2 is rejected');

select lives_ok(
  $$insert into public.transactions (account_id, txn_date, description_raw, amount)
    values ('a0000000-0000-0000-0000-000000000002', '2026-03-01', 'KROGER #123', -45.10)$$,
  'the same transaction on a different account is allowed');

update public.transactions set status = 'pending', txn_date = '2026-03-02'
 where id = '70000000-0000-0000-0000-000000000001';
select is(
  (select fingerprint from public.transactions where id = '70000000-0000-0000-0000-000000000001'),
  'a0000000-0000-0000-0000-000000000001|2026-03-02|-45.10|kroger123',
  'fingerprint is recomputed when the date changes (pending -> posted updates)');

select throws_ok(
  $$insert into public.transactions (account_id, txn_date, description_raw, amount, occurrence)
    values ('a0000000-0000-0000-0000-000000000001', '2026-03-05', 'X', -1, 0)$$,
  '23514', null, 'occurrence must be >= 1');

select * from finish();
rollback;
