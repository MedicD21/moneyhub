-- Phase 1: deleting an import_batch undoes it
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-10';

insert into public.accounts (id, name, kind) values ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking');
insert into public.debts (id, name, kind, apr, min_payment) values
  ('d0000000-0000-0000-0000-000000000001', 'Visa', 'credit_card', 24.99, 35);
insert into public.import_batches (id, account_id) values
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001'),
  ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001');

insert into public.transactions (id, account_id, import_batch_id, txn_date, description_raw, amount) values
  ('70000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', '2026-03-02', 'NETFLIX.COM', -15.49),
  ('70000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', '2026-03-03', 'KROGER', -20.00),
  ('70000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', '2026-03-04', 'SHELL', -30.00);
insert into public.balance_snapshots (account_id, import_batch_id, as_of_date, balance) values
  ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', '2026-03-03', 1000),
  ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', '2026-03-04', 970);
insert into public.debt_balances (debt_id, import_batch_id, as_of_date, balance) values
  ('d0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', '2026-03-03', 900);

insert into public.bills (id, name, amount, frequency, due_day) values
  ('e0000000-0000-0000-0000-000000000001', 'Netflix', 15.49, 'monthly', 5);
select public.ensure_bill_occurrences('2026-03-31');
select public.mark_bill_paid(
  (select id from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000001' and due_date = '2026-03-05'),
  '70000000-0000-0000-0000-000000000001');

select is((select status from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000001'),
          'paid', 'precondition: bill occurrence is paid by a transaction in batch 1');

delete from public.import_batches where id = 'b0000000-0000-0000-0000-000000000001';

select is((select count(*)::int from public.transactions where import_batch_id = 'b0000000-0000-0000-0000-000000000001'),
          0, 'batch transactions are deleted');
select is((select count(*)::int from public.balance_snapshots where import_batch_id = 'b0000000-0000-0000-0000-000000000001'),
          0, 'batch balance snapshots are deleted');
select is((select count(*)::int from public.debt_balances where import_batch_id = 'b0000000-0000-0000-0000-000000000001'),
          0, 'batch debt balances are deleted');
select is((select count(*)::int from public.transactions), 1, 'other batches are untouched (transactions)');
select is((select count(*)::int from public.balance_snapshots), 1, 'other batches are untouched (snapshots)');
select results_eq(
  $$select status, paid_amount, paid_date, transaction_id
      from public.bill_occurrences where bill_id = 'e0000000-0000-0000-0000-000000000001'$$,
  $$values ('due'::text, null::numeric, null::date, null::uuid)$$,
  'the bill the undone transaction paid goes back to due');
select is((select count(*)::int from public.import_batches), 1, 'only the named batch is gone');

select * from finish();
rollback;
