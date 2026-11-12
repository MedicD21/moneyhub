-- =============================================================================
-- Money Hub — LOCAL DEMO SEED (supabase start / supabase db reset only).
-- Never run this against your real project: it creates a demo user and fake data.
--
-- Demo login (local only): demo@moneyhub.local via magic link. With the
-- Supabase CLI the email lands in Mailpit at http://127.0.0.1:54324.
--
-- All dates are relative to app_today() so the demo always looks current.
-- =============================================================================
do $$
declare
  v_uid      uuid := '00000000-0000-4000-8000-000000000001';
  v_today    date := public.app_today();
  v_chk      uuid := '0a000000-0000-4000-8000-000000000001';
  v_sav      uuid := '0a000000-0000-4000-8000-000000000002';
  v_visa     uuid := '0a000000-0000-4000-8000-000000000003';
  v_d_visa   uuid := '0d000000-0000-4000-8000-000000000001';
  v_d_auto   uuid := '0d000000-0000-4000-8000-000000000002';
  v_d_stud   uuid := '0d000000-0000-4000-8000-000000000003';
  v_anchor   date;
  v_start    date := public.app_today() - 60;
  v_snap_old date := public.app_today() - 60;
  v_snap_new date := public.app_today() - 2;
  d          date;
  r          record;
  -- payoff simulation
  v_month    date;
  v_bal      jsonb;
  v_sched    jsonb := '[]';
  v_pool     numeric;
  v_int      numeric;
  v_pay      numeric;
  v_b        numeric;
  v_total_interest numeric := 0;
  v_free     date;
  i          int;
  dd         record;
begin
  -- ---- Auth user (full GoTrue columns when present, minimal otherwise) ----
  if exists (select 1 from information_schema.columns
              where table_schema = 'auth' and table_name = 'users' and column_name = 'encrypted_password') then
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, email_change, email_change_token_new, recovery_token)
    values ('00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
            'demo@moneyhub.local', '', now(),
            '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '')
    on conflict (id) do nothing;
    if exists (select 1 from information_schema.tables where table_schema = 'auth' and table_name = 'identities') then
      insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), v_uid, v_uid::text,
              jsonb_build_object('sub', v_uid::text, 'email', 'demo@moneyhub.local', 'email_verified', true),
              'email', now(), now(), now())
      on conflict do nothing;
    end if;
  else
    insert into auth.users (id, email) values (v_uid, 'demo@moneyhub.local') on conflict (id) do nothing;
  end if;

  perform public.bootstrap_owner('demo@moneyhub.local');

  -- ---- Accounts ----
  insert into public.accounts (id, name, institution, kind, last4) values
    (v_chk,  'Checking',     'Demo Bank', 'checking',    '1234'),
    (v_sav,  'Savings',      'Demo Bank', 'savings',     '5678'),
    (v_visa, 'Rewards Visa', 'Demo Card', 'credit_card', '9012');

  -- ---- Rules ----
  insert into public.merchant_rules (pattern, merchant, category_id)
  select x.pattern, x.merchant, c.id
  from (values ('KROGER','Kroger','Groceries'), ('SHELL','Shell','Gas'), ('NETFLIX','Netflix','Subscriptions'),
               ('STARBUCKS','Starbucks','Dining'), ('PAYROLL','Employer payroll','Income'),
               ('TARGET','Target','Shopping'), ('CHIPOTLE','Chipotle','Dining')) x(pattern, merchant, cat)
  join public.categories c on c.name = x.cat;

  -- ---- Income: biweekly, anchored on the most recent Friday ----
  v_anchor := v_today - ((extract(isodow from v_today)::int + 2) % 7);
  insert into public.income_sources (name, frequency, anchor_date, expected_net, deposit_account_id)
  values ('Paycheck', 'biweekly', v_anchor, 2450.00, v_chk);

  -- ---- Bills ----
  insert into public.bills (name, amount, is_variable, frequency, due_day, anchor_date, autopay,
                            pay_from_account_id, category_id, match_pattern)
  select x.name, x.amount, x.variable, x.freq, x.due_day, x.anchor, x.autopay, v_chk, c.id, x.pattern
  from (values
    ('Rent',          1450.00, false, 'monthly',  1, null::date, false, 'Housing',        'RENT PMT'),
    ('Electric',       140.00, true,  'monthly', 18, null,       true,  'Utilities',      'DUKE ENERGY'),
    ('Internet',        75.00, false, 'monthly', 22, null,       true,  'Phone/Internet', 'XFINITY'),
    ('Phone',           85.00, false, 'monthly', 12, null,       true,  'Phone/Internet', 'VERIZON'),
    ('Netflix',         15.49, false, 'monthly',  5, null,       true,  'Subscriptions',  'NETFLIX'),
    ('Car insurance',  160.00, false, 'monthly', 27, null,       true,  'Insurance',      'GEICO'),
    ('Gym',             40.00, false, 'monthly',  3, null,       true,  'Entertainment',  'PLANET FIT')
  ) x(name, amount, variable, freq, due_day, anchor, autopay, cat, pattern)
  join public.categories c on c.name = x.cat;

  -- ---- Debts ----
  insert into public.debts (id, name, kind, account_id, apr, min_payment, due_day, credit_limit) values
    (v_d_visa, 'Rewards Visa', 'credit_card', v_visa, 24.990,  40.00, 15, 5000),
    (v_d_auto, 'Auto loan',    'auto',        null,    6.900, 385.00, 20, null),
    (v_d_stud, 'Student loan', 'student',     null,    5.500, 210.00, 25, null);
  insert into public.debt_balances (debt_id, as_of_date, balance) values
    (v_d_auto, v_today - 40, 14210.55), (v_d_auto, v_today - 10, 13902.30),
    (v_d_stud, v_today - 40, 21870.00), (v_d_stud, v_today - 10, 21760.12);

  insert into public.set_asides (name, per_paycheck) values ('Emergency fund', 150), ('Buffer', 50);

  -- ---- Transactions (checking) ----
  insert into public.balance_snapshots (account_id, as_of_date, balance) values (v_chk, v_snap_old, 3180.42);

  for d in select generate_series(v_start + 1, v_today, interval '1 day')::date loop
    -- paydays
    if exists (select 1 from public.pay_dates(d, d)) then
      insert into public.transactions (account_id, txn_date, description_raw, amount, merchant, category_id)
      values (v_chk, d, 'ACME CORP PAYROLL', 2450.00, 'Employer payroll', (select id from public.categories where name = 'Income'));
    end if;
    -- bills paid on their due day from checking
    for r in select b.* from public.bills b where b.due_day = extract(day from d) loop
      insert into public.transactions (account_id, txn_date, description_raw, amount, category_id)
      values (v_chk, d, r.match_pattern || ' ' || to_char(d, 'MMDD'),
              -(case when r.is_variable then r.amount - 12.37 + (extract(day from d)::int % 5) * 4 else r.amount end),
              r.category_id);
    end loop;
    -- debt payments
    if extract(day from d) = 20 then
      insert into public.transactions (account_id, txn_date, description_raw, amount, category_id, debt_id)
      values (v_chk, d, 'ALLY AUTO LOAN PMT', -385.00, (select id from public.categories where name = 'Debt Payment'), v_d_auto);
    end if;
    if extract(day from d) = 25 then
      insert into public.transactions (account_id, txn_date, description_raw, amount, category_id, debt_id)
      values (v_chk, d, 'NELNET STUDENT LOAN', -210.00, (select id from public.categories where name = 'Debt Payment'), v_d_stud);
    end if;
    if extract(day from d) = 14 then
      insert into public.transactions (account_id, txn_date, description_raw, amount, category_id, debt_id)
      values (v_chk, d, 'PAYMENT TO REWARDS VISA', -300.00, (select id from public.categories where name = 'Credit Card Payment'), v_d_visa);
      insert into public.transactions (account_id, txn_date, description_raw, amount, category_id)
      values (v_visa, d, 'PAYMENT THANK YOU', 300.00, (select id from public.categories where name = 'Credit Card Payment'));
    end if;
    -- everyday spending
    if extract(isodow from d) = 6 then
      insert into public.transactions (account_id, txn_date, description_raw, amount, merchant, category_id)
      values (v_chk, d, 'KROGER #0412', -(118.40 + (extract(day from d)::int % 7) * 6.15), 'Kroger',
              (select id from public.categories where name = 'Groceries'));
    end if;
    if extract(isodow from d) = 3 then
      insert into public.transactions (account_id, txn_date, description_raw, amount, merchant, category_id)
      values (v_visa, d, 'SHELL OIL 57442', -(41.20 + (extract(day from d)::int % 4) * 3.10), 'Shell',
              (select id from public.categories where name = 'Gas'));
    end if;
    if extract(isodow from d) in (2, 5) then
      insert into public.transactions (account_id, txn_date, description_raw, amount, merchant, category_id)
      values (v_visa, d, 'CHIPOTLE 2291', -(14.85 + (extract(day from d)::int % 3) * 2.40), 'Chipotle',
              (select id from public.categories where name = 'Dining'));
    end if;
    if extract(day from d) in (9, 23) then
      insert into public.transactions (account_id, txn_date, description_raw, amount, merchant, category_id)
      values (v_visa, d, 'TARGET T-1123', -64.32, 'Target', (select id from public.categories where name = 'Shopping'));
    end if;
    if extract(day from d) = 10 then
      insert into public.transactions (account_id, txn_date, description_raw, amount, category_id)
      values (v_chk, d, 'TRANSFER TO SAVINGS', -200.00, (select id from public.categories where name = 'Transfer'));
      insert into public.transactions (account_id, txn_date, description_raw, amount, category_id)
      values (v_sav, d, 'TRANSFER FROM CHECKING', 200.00, (select id from public.categories where name = 'Transfer'));
    end if;
  end loop;

  -- A pending row and an item waiting for review
  insert into public.transactions (account_id, txn_date, description_raw, amount, status)
  values (v_chk, v_today - 1, 'SQ *CORNER CAFE', -8.75, 'pending');
  insert into public.transactions (account_id, txn_date, description_raw, amount, needs_review, review_question)
  values (v_chk, v_today - 4, 'POS PURCHASE 88213 ANYTOWN', -37.18, true,
          'Unrecognized merchant "POS PURCHASE 88213". What was this for?');

  -- Snapshots that reconcile exactly (balance check = 0)
  insert into public.balance_snapshots (account_id, as_of_date, balance)
  select v_chk, v_snap_new,
         3180.42 + coalesce(sum(t.amount), 0)
  from public.transactions t
  where t.account_id = v_chk and t.status = 'posted' and t.txn_date > v_snap_old and t.txn_date <= v_snap_new;

  insert into public.balance_snapshots (account_id, as_of_date, balance) values (v_sav, v_today - 20, 4200.00);
  insert into public.balance_snapshots (account_id, as_of_date, balance) values (v_visa, v_today - 60, 1840.66);
  insert into public.balance_snapshots (account_id, as_of_date, balance)
  select v_visa, v_today - 3, 1840.66 - coalesce(sum(t.amount), 0)  -- owed goes up when amount < 0
  from public.transactions t
  where t.account_id = v_visa and t.status = 'posted' and t.txn_date > v_today - 60 and t.txn_date <= v_today - 3;

  -- Bill occurrences, then link the payments made this month
  perform public.ensure_bill_occurrences();
  for r in select m.occurrence_id, m.transaction_id from public.v_bill_match_candidates m where m.rank = 1 loop
    begin
      perform public.mark_bill_paid(r.occurrence_id, r.transaction_id);
    exception when others then null;  -- an occurrence already matched by another payment
    end;
  end loop;

  -- ---- Demo debt plan (stand-in for what Claude computes with code execution) ----
  select jsonb_object_agg(vd.debt_id::text, vd.balance) into v_bal from public.v_debts vd where vd.balance > 0;
  v_month := date_trunc('month', v_today::timestamp)::date + interval '1 month';
  for i in 1..120 loop
    exit when (select coalesce(sum(value::numeric), 0) from jsonb_each_text(v_bal)) <= 0;
    v_pool := 200;  -- extra per month
    -- minimums first
    for dd in select d2.id, d2.apr, d2.min_payment from public.debts d2 where v_bal ? d2.id::text order by d2.apr desc loop
      v_b   := (v_bal->>dd.id::text)::numeric;
      continue when v_b <= 0;
      v_int := round(v_b * dd.apr / 1200, 2);
      v_pay := least(dd.min_payment, v_b + v_int);
      v_pool := v_pool + (dd.min_payment - v_pay);  -- rollover from a paid-off debt
      v_total_interest := v_total_interest + v_int;
      v_sched := v_sched || jsonb_build_object('month', to_char(v_month, 'YYYY-MM'), 'debt_id', dd.id,
                   'start', v_b, 'interest', v_int, 'payment', v_pay, 'end', v_b + v_int - v_pay);
      v_bal := jsonb_set(v_bal, array[dd.id::text], to_jsonb(v_b + v_int - v_pay));
    end loop;
    -- extra to the highest APR (avalanche)
    for dd in select d2.id from public.debts d2 where v_bal ? d2.id::text order by d2.apr desc loop
      v_b := (v_bal->>dd.id::text)::numeric;
      continue when v_b <= 0 or v_pool <= 0;
      v_pay := least(v_pool, v_b);
      v_pool := v_pool - v_pay;
      v_bal := jsonb_set(v_bal, array[dd.id::text], to_jsonb(v_b - v_pay));
      v_sched := (select jsonb_agg(case when e->>'debt_id' = dd.id::text and e->>'month' = to_char(v_month, 'YYYY-MM')
                                        then jsonb_set(jsonb_set(e, '{payment}', to_jsonb((e->>'payment')::numeric + v_pay)),
                                                       '{end}', to_jsonb((e->>'end')::numeric - v_pay))
                                        else e end) from jsonb_array_elements(v_sched) e);
    end loop;
    v_free := v_month;
    v_month := v_month + interval '1 month';
  end loop;

  insert into public.debt_plans (name, strategy, extra_monthly, assumptions, summary, schedule, balances_as_of, is_active)
  values ('Avalanche + $200/mo (demo)', 'avalanche', 200,
          jsonb_build_object('start_month', to_char(date_trunc('month', v_today::timestamp) + interval '1 month', 'YYYY-MM'),
                             'new_charges', 'assumed to stop', 'apr_changes', 'none'),
          jsonb_build_object('debt_free_month', to_char(v_free, 'YYYY-MM'), 'total_interest', round(v_total_interest, 2)),
          v_sched, v_today - 3, true);
end;
$$;
