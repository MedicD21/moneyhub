-- Phase 1: the remaining views + the cron job
begin;
create extension if not exists pgtap with schema extensions;
-- Start from empty tables (rolled back with the test), so the suite also runs on a seeded DB.
truncate public.app_settings, public.accounts, public.import_batches, public.categories,
  public.transactions, public.balance_snapshots, public.merchant_rules, public.income_sources,
  public.bills, public.bill_occurrences, public.debts, public.debt_balances, public.set_asides,
  public.debt_plans cascade;
select plan(17);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'owner@test.local');
select public.bootstrap_owner('owner@test.local');
set local app.today = '2026-03-10';

insert into public.accounts (id, name, kind) values
  ('a0000000-0000-0000-0000-000000000001', 'Checking', 'checking'),
  ('a0000000-0000-0000-0000-000000000002', 'Savings',  'savings'),
  ('a0000000-0000-0000-0000-000000000003', 'Visa',     'credit_card'),
  ('a0000000-0000-0000-0000-000000000004', 'Store card', 'credit_card');
insert into public.balance_snapshots (account_id, as_of_date, balance) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-08', 1500.00),
  ('a0000000-0000-0000-0000-000000000002', '2026-02-20', 3000.00),
  ('a0000000-0000-0000-0000-000000000003', '2026-03-09', 440.00),
  ('a0000000-0000-0000-0000-000000000004', '2026-03-01', 60.00);

insert into public.debts (id, name, kind, account_id, apr, min_payment, due_day, credit_limit, promo_apr, promo_ends) values
  ('d0000000-0000-0000-0000-000000000001', 'Visa', 'credit_card', 'a0000000-0000-0000-0000-000000000003', 24.99, 35, 12, 2000, 0, '2026-06-30'),
  ('d0000000-0000-0000-0000-000000000002', 'Car loan', 'auto', null, 6.9, 300, 17, null, null, null);
insert into public.debt_balances (debt_id, as_of_date, balance) values
  ('d0000000-0000-0000-0000-000000000001', '2026-03-01', 500.00),   -- older than the account screenshot
  ('d0000000-0000-0000-0000-000000000002', '2026-02-28', 9000.00),
  ('d0000000-0000-0000-0000-000000000002', '2026-01-31', 9300.00);

-- Transactions in March
insert into public.transactions (account_id, txn_date, description_raw, amount, category_id, needs_review) values
  ('a0000000-0000-0000-0000-000000000001', '2026-03-01', 'PAYROLL', 2000, (select id from public.categories where name='Income'), false),
  ('a0000000-0000-0000-0000-000000000001', '2026-03-02', 'KROGER',  -100, (select id from public.categories where name='Groceries'), false),
  ('a0000000-0000-0000-0000-000000000001', '2026-03-03', 'KROGER RETURN', 20, (select id from public.categories where name='Groceries'), false),
  ('a0000000-0000-0000-0000-000000000001', '2026-03-04', 'VISA PAYMENT', -300, (select id from public.categories where name='Credit Card Payment'), false),
  ('a0000000-0000-0000-0000-000000000001', '2026-03-05', 'ALLY AUTO', -300, (select id from public.categories where name='Debt Payment'), false),
  ('a0000000-0000-0000-0000-000000000001', '2026-03-06', 'MYSTERY', -7.5, null, true),
  ('a0000000-0000-0000-0000-000000000001', '2026-02-15', 'KROGER',  -50, (select id from public.categories where name='Groceries'), false);

select results_eq(
  $$select category_name, total_out, total_in, net, txn_count::int from public.v_month_spending
     where month = '2026-03-01' order by category_name$$,
  $$values ('Debt Payment'::text, 300.00::numeric, 0::numeric, -300.00::numeric, 1),
           ('Groceries', 100.00, 20.00, -80.00, 2),
           ('Income', 0, 2000.00, 2000.00, 1),
           ('Uncategorized', 7.50, 0, -7.50, 1)$$,
  'v_month_spending groups by month x category and excludes transfers (credit card payment)');

select results_eq(
  $$select month, income, spending, net, uncategorized_count::int from public.v_cash_flow order by month$$,
  $$values ('2026-02-01'::date, 0::numeric, 50.00::numeric, -50.00::numeric, 0),
           ('2026-03-01', 2000.00, 387.50, 1612.50, 1)$$,
  'v_cash_flow: spending = 100 - 20 refund + 300 debt + 7.50 uncategorized; transfers excluded');

-- Bills
insert into public.bills (name, amount, frequency, due_day, anchor_date, autopay) values
  ('Lawn',     10, 'weekly',   null, '2026-03-02', false),
  ('Daycare', 100, 'biweekly', null, '2026-03-06', true),
  ('Rent',     50, 'monthly',  9,    null,         true),
  ('Water',    90, 'quarterly', 20,  '2026-03-20', false),
  ('Prime',   120, 'annual',   null, '2026-03-12', false);
insert into public.bills (name, amount, frequency, due_day, is_active) values ('Old gym', 999, 'monthly', 1, false);
select results_eq(
  $$select monthly_total, autopay_monthly_total, active_bill_count::int from public.v_monthly_bills_total$$,
  $$values (350.00::numeric, 266.67::numeric, 5)$$,
  'v_monthly_bills_total: 10*52/12 + 100*26/12 + 50 + 90/3 + 120/12 = 350.00 (inactive excluded)');

select public.ensure_bill_occurrences('2026-04-30');
select results_eq(
  $$select bill_name, overdue, days_until_due from public.v_bill_status where due_date = '2026-03-09' order by bill_name$$,
  $$values ('Lawn'::text, true, -1), ('Rent', true, -1)$$,
  'v_bill_status flags unpaid past-due occurrences as overdue');
select ok(
  (select bool_and(status in ('due','partial') and due_date <= '2026-04-09') from public.v_upcoming_bills),
  'v_upcoming_bills only has unpaid occurrences due within 30 days');
select ok(exists(select 1 from public.v_upcoming_bills where overdue),
          'v_upcoming_bills includes overdue occurrences');

-- Debts
select results_eq(
  $$select name, balance, balance_as_of, balance_source, utilization_pct, effective_apr, next_due_date
      from public.v_debts order by name$$,
  $$values ('Car loan'::text, 9000.00::numeric, '2026-02-28'::date, 'debt_balances'::text, null::numeric, 6.900::numeric, '2026-03-17'::date),
           ('Visa', 440.00, '2026-03-09', 'account_snapshot', 22.0, 0.000, '2026-03-12')$$,
  'v_debts: newest source wins, utilization from credit_limit, promo APR applies until promo_ends');

-- Dashboard
select results_eq(
  $$select total_cash, total_debt, net from public.v_dashboard$$,
  -- cash: checking 1500 (txns on/before 03-08 are already in it) + savings 3000
  -- debt: Visa 440 + Car 9000 + unlinked Store card 60
  $$values (4500.00::numeric, 9500.00::numeric, -5000.00::numeric)$$,
  'v_dashboard totals: cash, debt (incl. liability accounts with no debt row), net');
select results_eq(
  $$select review_queue_count::int, oldest_data_days, accounts_without_snapshot::int, balance_check_issues::int
      from public.v_dashboard$$,
  $$values (1, 18, 0, 0)$$,
  'v_dashboard review count and data age (savings screenshot is 18 days old)');
select results_eq(
  $$select bills_due_7d_count::int, overdue_bills_count::int from public.v_dashboard$$,
  $$values (2, 4)$$,
  'v_dashboard: due in next 7 days = Prime 03-12, Lawn 03-16; overdue = Lawn 03-02, Daycare 03-06, Lawn 03-09, Rent 03-09');
select is((select safe_to_spend from public.v_dashboard), null::numeric,
          'v_dashboard safe_to_spend is null when there is no income source');
select is((select count(*)::int from public.v_dashboard), 1, 'v_dashboard always returns exactly one row');

-- Review queue
select results_eq($$select description_raw from public.v_review_queue$$, $$values ('MYSTERY'::text)$$,
                  'v_review_queue lists needs_review transactions');

-- Debt plan views
insert into public.debt_plans (name, strategy, extra_monthly, assumptions, summary, schedule, balances_as_of, is_active)
values ('Avalanche', 'avalanche', 200, '{}', '{"debt_free":"2027-01"}',
  '[{"month":"2026-04","debt_id":"d0000000-0000-0000-0000-000000000001","start":440,"interest":0,"payment":235,"end":205},
    {"month":"2026-04","debt_id":"d0000000-0000-0000-0000-000000000002","start":9000,"interest":51.75,"payment":300,"end":8751.75},
    {"month":"2026-05","debt_id":"d0000000-0000-0000-0000-000000000001","start":205,"interest":0,"payment":205,"end":0}]',
  '2026-03-09', true);
select results_eq(
  $$select month, total_end_balance from public.v_debt_plan_projection order by month$$,
  $$values ('2026-04-01'::date, 8956.75::numeric), ('2026-05-01', 0.00)$$,
  'v_debt_plan_projection sums the active plan schedule per month');
select throws_ok(
  $$insert into public.debt_plans (name, strategy, assumptions, summary, schedule, balances_as_of, is_active)
    values ('Second', 'snowball', '{}', '{}', '[]', '2026-03-09', true)$$,
  '23505', null, 'only one debt plan can be active');
select is((select count(*)::int from public.v_debt_balance_history where debt_name = 'Visa'), 2,
          'v_debt_balance_history merges debt_balances and linked account snapshots');

-- Cron
select ok(
  not exists(select 1 from pg_extension where extname = 'pg_cron')
  or exists(select 1 from cron.job where jobname = 'ensure-bill-occurrences' and schedule = '0 5 * * *'),
  'pg_cron job ensure-bill-occurrences runs daily at 05:00 UTC');

select * from finish();
rollback;
