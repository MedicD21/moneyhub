-- =============================================================================
-- Money Hub — core schema (tables = facts)
-- See SPEC.md §3 and docs/SPEC_REVIEW.md for deviations from the original spec.
--
-- Sign convention: transactions.amount  negative = money out, positive = money in.
-- balance_snapshots.balance / debt_balances.balance are stored AS DISPLAYED by
-- the bank (a credit card owing $500 is stored as 500). Views convert liability
-- balances to the signed convention (-500) before doing any math.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- app_settings: exactly one row. Holds the owner's auth user id so Claude's
-- privileged writes (where auth.uid() is null) get the right owner_id.
-- ---------------------------------------------------------------------------
create table public.app_settings (
  id                     boolean primary key default true check (id),  -- forces a single row
  owner_id               uuid not null unique references auth.users(id) on delete cascade,
  timezone               text not null default 'America/New_York',
  low_balance_threshold  numeric(12,2) not null default 100.00,
  stale_after_days       int not null default 7 check (stale_after_days > 0),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);
comment on table public.app_settings is
  'Single-row settings. owner_id = the one Supabase Auth user who owns all data.';

-- ---------------------------------------------------------------------------
-- Helper functions used by column defaults, generated columns and views.
-- ---------------------------------------------------------------------------

-- owner for new rows: the logged-in user if any, else the configured owner.
-- (SPEC §6.3 proposed a subquery DEFAULT, which Postgres does not allow.)
create or replace function public.app_owner_id()
returns uuid
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.uid(), (select s.owner_id from public.app_settings s where s.id));
$$;
comment on function public.app_owner_id() is
  'Default owner_id: auth.uid() when called by a logged-in user, else app_settings.owner_id.';

-- "today" in the owner's timezone. The app.today GUC is a test hook that lets
-- SQL tests pin the date (set local app.today = ''2026-03-10'').
create or replace function public.app_today()
returns date
language sql
stable
set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('app.today', true), '')::date,
    (now() at time zone coalesce(
        (select s.timezone from public.app_settings s where s.id),
        'America/New_York'))::date
  );
$$;
comment on function public.app_today() is
  'Current date in app_settings.timezone (override with the app.today setting for tests).';

-- Description normalizer used for fingerprints and fuzzy matching.
create or replace function public.normalize_desc(p_text text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select lower(regexp_replace(coalesce(p_text, ''), '[^a-zA-Z0-9]', '', 'g'));
$$;

-- Fingerprint of a transaction. Declared IMMUTABLE so it can back a generated
-- column (a raw date::text cast is only STABLE because it depends on DateStyle;
-- to_char with an explicit ISO pattern is deterministic).
create or replace function public.txn_fingerprint(
  p_account_id uuid, p_txn_date date, p_amount numeric, p_description text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select p_account_id::text || '|' || to_char(p_txn_date, 'YYYY-MM-DD') || '|'
      || (p_amount::numeric(12,2))::text || '|' || public.normalize_desc(p_description);
$$;

-- Generic updated_at trigger.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.accounts (
  id                        uuid primary key default gen_random_uuid(),
  owner_id                  uuid not null default public.app_owner_id(),
  name                      text not null,
  institution               text,
  kind                      text not null check (kind in ('checking','savings','credit_card','loan','cash')),
  last4                     text check (last4 is null or last4 ~ '^[0-9]{2,6}$'),
  balance_includes_pending  boolean not null default false,
  is_active                 boolean not null default true,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  unique (owner_id, name)
);
comment on column public.accounts.balance_includes_pending is
  'true if the balance this bank displays already includes pending transactions (used by v_balance_check).';

create table public.import_batches (
  id                     uuid primary key default gen_random_uuid(),
  owner_id               uuid not null default public.app_owner_id(),
  account_id             uuid references public.accounts(id),
  source                 text not null default 'screenshot' check (source in ('screenshot','manual','chat')),
  screenshot_range_start date,
  screenshot_range_end   date,
  rows_inserted          int not null default 0,
  rows_updated           int not null default 0,
  notes                  text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  check (screenshot_range_start is null or screenshot_range_end is null
         or screenshot_range_start <= screenshot_range_end)
);

create table public.categories (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default public.app_owner_id(),
  name         text not null,
  parent_name  text,
  kind         text not null check (kind in ('expense','income','transfer','debt_payment')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (owner_id, name)
);

create table public.transactions (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null default public.app_owner_id(),
  account_id         uuid not null references public.accounts(id),
  import_batch_id    uuid references public.import_batches(id) on delete cascade,
  txn_date           date not null,
  description_raw    text not null,
  merchant           text,
  amount             numeric(12,2) not null,
  status             text not null default 'posted' check (status in ('pending','posted')),
  category_id        uuid references public.categories(id),
  tags               text[] not null default '{}',
  needs_review       boolean not null default false,
  review_question    text,
  fingerprint        text generated always as
                       (public.txn_fingerprint(account_id, txn_date, amount, description_raw)) stored,
  occurrence         int not null default 1 check (occurrence >= 1),
  bill_occurrence_id uuid,
  debt_id            uuid,
  note               text,
  pending_txn_date   date,         -- set automatically when a pending row posts: its date while pending
  posted_at          timestamptz,  -- set automatically when a pending row posts
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (account_id, fingerprint, occurrence)
);
comment on column public.transactions.amount is 'negative = money out, positive = money in';
comment on column public.transactions.occurrence is
  '1 for the first transaction with a given fingerprint, 2 for an identical second one, etc.';

create table public.balance_snapshots (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null default public.app_owner_id(),
  account_id       uuid not null references public.accounts(id),
  import_batch_id  uuid references public.import_batches(id) on delete cascade,
  as_of_date       date not null,
  balance          numeric(12,2) not null,
  available        numeric(12,2),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
comment on column public.balance_snapshots.balance is
  'Balance exactly as the bank displays it. Credit card / loan: amount owed as a positive number.';

create table public.merchant_rules (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default public.app_owner_id(),
  pattern      text not null check (length(trim(pattern)) >= 2),
  merchant     text,
  category_id  uuid references public.categories(id),
  tags         text[] not null default '{}',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (owner_id, pattern)
);
comment on column public.merchant_rules.pattern is 'Case-insensitive substring of transactions.description_raw.';

create table public.income_sources (
  id                  uuid primary key default gen_random_uuid(),
  owner_id            uuid not null default public.app_owner_id(),
  name                text not null,
  frequency           text not null check (frequency in ('weekly','biweekly','semimonthly','monthly')),
  anchor_date         date not null,
  semimonthly_days    int[],
  weekend_adjust      text not null default 'none'
                        check (weekend_adjust in ('none','previous_business_day','next_business_day')),
  expected_net        numeric(12,2) not null check (expected_net >= 0),
  deposit_account_id  uuid references public.accounts(id),
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (frequency <> 'semimonthly'
         or (semimonthly_days is not null and cardinality(semimonthly_days) between 1 and 4
             and 1 <= all(semimonthly_days) and 31 >= all(semimonthly_days)))
);
comment on column public.income_sources.weekend_adjust is
  'If a payday lands on Sat/Sun: none, previous_business_day (Fri) or next_business_day (Mon). Holidays are not modelled.';

create table public.bills (
  id                   uuid primary key default gen_random_uuid(),
  owner_id             uuid not null default public.app_owner_id(),
  name                 text not null,
  amount               numeric(12,2) not null check (amount >= 0),
  is_variable          boolean not null default false,
  frequency            text not null check (frequency in ('weekly','biweekly','monthly','quarterly','annual')),
  due_day              int check (due_day between 1 and 31),
  anchor_date          date,
  autopay              boolean not null default false,
  pay_from_account_id  uuid references public.accounts(id),
  category_id          uuid references public.categories(id),
  match_pattern        text,
  is_active            boolean not null default true,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  check (case frequency
           when 'weekly'    then anchor_date is not null
           when 'biweekly'  then anchor_date is not null
           when 'monthly'   then due_day is not null or anchor_date is not null
           else anchor_date is not null  -- quarterly / annual: anchor gives the month
         end)
);
comment on column public.bills.amount is 'Expected amount as a positive number.';
comment on column public.bills.due_day is 'Day of month (monthly/quarterly/annual). 29-31 clamp to the last day of short months.';

create table public.bill_occurrences (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null default public.app_owner_id(),
  bill_id          uuid not null references public.bills(id) on delete cascade,
  due_date         date not null,
  expected_amount  numeric(12,2) not null check (expected_amount >= 0),
  paid_amount      numeric(12,2) check (paid_amount is null or paid_amount >= 0),
  paid_date        date,
  status           text not null default 'due' check (status in ('due','paid','partial','skipped')),
  transaction_id   uuid references public.transactions(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (bill_id, due_date)
);

create table public.debts (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default public.app_owner_id(),
  name          text not null,
  kind          text not null check (kind in ('credit_card','auto','student','personal','medical','mortgage','other')),
  account_id    uuid references public.accounts(id),
  apr           numeric(6,3) not null check (apr >= 0),
  min_payment   numeric(12,2) not null check (min_payment >= 0),
  due_day       int check (due_day between 1 and 31),
  credit_limit  numeric(12,2) check (credit_limit is null or credit_limit > 0),
  promo_apr     numeric(6,3) check (promo_apr is null or promo_apr >= 0),
  promo_ends    date,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
comment on column public.debts.apr is '24.990 = 24.99%';
comment on column public.debts.credit_limit is 'Credit cards only; enables utilization in v_debts.';

create table public.debt_balances (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null default public.app_owner_id(),
  debt_id          uuid not null references public.debts(id) on delete cascade,
  import_batch_id  uuid references public.import_batches(id) on delete cascade,
  as_of_date       date not null,
  balance          numeric(12,2) not null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
comment on column public.debt_balances.balance is 'Amount owed as a positive number. Never overwrite: insert a new row.';

create table public.set_asides (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default public.app_owner_id(),
  name          text not null,
  per_paycheck  numeric(12,2) not null check (per_paycheck >= 0),
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table public.debt_plans (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null default public.app_owner_id(),
  name             text not null,
  strategy         text not null check (strategy in ('avalanche','snowball','custom','minimums_only')),
  extra_monthly    numeric(12,2) not null default 0 check (extra_monthly >= 0),
  assumptions      jsonb not null,
  summary          jsonb not null,
  schedule         jsonb not null check (jsonb_typeof(schedule) = 'array'),
  balances_as_of   date not null,
  is_active        boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
comment on column public.debt_plans.schedule is
  'JSON array of {month:"YYYY-MM", debt_id, start, interest, payment, end}.';

alter table public.transactions
  add constraint fk_bill_occ foreign key (bill_occurrence_id)
    references public.bill_occurrences(id) on delete set null,
  add constraint fk_debt foreign key (debt_id)
    references public.debts(id) on delete set null;

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
create index transactions_account_date_idx   on public.transactions (account_id, txn_date);
create index transactions_needs_review_idx   on public.transactions (needs_review) where needs_review;
create index transactions_batch_idx          on public.transactions (import_batch_id);
create index transactions_debt_idx           on public.transactions (debt_id) where debt_id is not null;
create index transactions_pending_idx        on public.transactions (account_id, amount) where status = 'pending';
create index bill_occurrences_due_date_idx   on public.bill_occurrences (due_date);
create index bill_occurrences_txn_idx        on public.bill_occurrences (transaction_id) where transaction_id is not null;
create index balance_snapshots_acct_date_idx on public.balance_snapshots (account_id, as_of_date desc);
create index balance_snapshots_batch_idx     on public.balance_snapshots (import_batch_id);
create index debt_balances_debt_date_idx     on public.debt_balances (debt_id, as_of_date desc);
create index debt_balances_batch_idx         on public.debt_balances (import_batch_id);
-- Only one active debt plan at a time (it feeds paycheck_plan().extra_debt).
create unique index debt_plans_one_active_idx on public.debt_plans (owner_id) where is_active;

-- ---------------------------------------------------------------------------
-- updated_at triggers on every table that has the column
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'app_settings','accounts','import_batches','categories','transactions','balance_snapshots',
    'merchant_rules','income_sources','bills','bill_occurrences','debts','debt_balances',
    'set_asides','debt_plans']
  loop
    execute format(
      'create trigger set_updated_at before update on public.%I
         for each row execute function public.set_updated_at()', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Integrity triggers
-- ---------------------------------------------------------------------------

-- Record when a pending transaction posts (used by the balance views to know
-- whether the row was inside an earlier balance snapshot).
create or replace function public.track_transaction_posting()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'pending' and new.status = 'posted' then
    new.posted_at        := now();
    new.pending_txn_date := coalesce(old.pending_txn_date, old.txn_date);
  end if;
  return new;
end;
$$;

create trigger track_transaction_posting
  before update of status on public.transactions
  for each row execute function public.track_transaction_posting();

-- Is transaction r OUTSIDE (not yet reflected in) a balance snapshot taken as of
-- p_as_of and recorded at p_snap_created?
--   Bank balance excludes pending (default):
--     outside if still pending, dated after the snapshot, dated on the snapshot
--     day but recorded after it, or it was still pending when the snapshot was
--     recorded (posted_at later).
--   Bank balance includes pending:
--     outside if its original date (the pending date if it was pending) is
--     after the snapshot, or it is on the snapshot day and recorded after it.
-- Rows written in the same transaction as the snapshot (commit_screenshot_import)
-- share its timestamp and count as inside.
create or replace function public.txn_outside_snapshot(
  p_status text, p_txn_date date, p_pending_txn_date date, p_posted_at timestamptz,
  p_created_at timestamptz, p_as_of date, p_snap_created timestamptz, p_includes_pending boolean)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when p_includes_pending then
         coalesce(p_pending_txn_date, p_txn_date) > p_as_of
      or (coalesce(p_pending_txn_date, p_txn_date) = p_as_of and p_created_at > p_snap_created)
    else
         p_status = 'pending'
      or p_txn_date > p_as_of
      or (p_txn_date = p_as_of and p_created_at > p_snap_created)
      or (p_posted_at is not null and p_posted_at > p_snap_created)
  end;
$$;

-- Bill occurrence payment state is derived from ALL transactions linked to it
-- (transactions.bill_occurrence_id), so partial payments, undo (batch delete)
-- and re-linking always recompute correctly. Outflows count as payment,
-- refunds linked to the occurrence reduce it.
create or replace function public.recalc_bill_occurrence(p_occurrence_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_paid   numeric(12,2);
  v_date   date;
  v_last   uuid;
  v_n      int;
begin
  if p_occurrence_id is null then return; end if;

  select -sum(t.amount), max(t.txn_date), count(*),
         (array_agg(t.id order by t.txn_date desc, t.created_at desc))[1]
    into v_paid, v_date, v_n, v_last
  from public.transactions t
  where t.bill_occurrence_id = p_occurrence_id;

  update public.bill_occurrences o
     set paid_amount    = case when v_n > 0 then greatest(v_paid, 0) end,
         paid_date      = case when v_n > 0 then v_date end,
         transaction_id = v_last,
         status = case
                    when v_n = 0 or coalesce(v_paid, 0) <= 0
                      then case when o.status = 'skipped' then 'skipped' else 'due' end
                    when b.is_variable or v_paid >= o.expected_amount then 'paid'
                    else 'partial'
                  end
    from public.bills b
   where o.id = p_occurrence_id and b.id = o.bill_id;
end;
$$;

create or replace function public.transactions_bill_link_changed()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE','DELETE') then
    perform public.recalc_bill_occurrence(old.bill_occurrence_id);
  end if;
  if tg_op in ('INSERT','UPDATE')
     and new.bill_occurrence_id is distinct from (case when tg_op = 'UPDATE' then old.bill_occurrence_id end)
     or (tg_op = 'UPDATE' and new.amount is distinct from old.amount) then
    perform public.recalc_bill_occurrence(new.bill_occurrence_id);
  end if;
  return null;
end;
$$;

-- Fires for cascaded deletes too (undoing an import batch un-pays its bills).
create trigger transactions_bill_link_changed
  after insert or delete or update of bill_occurrence_id, amount on public.transactions
  for each row execute function public.transactions_bill_link_changed();

-- Keep future, still-unpaid occurrences in sync with their bill.
create or replace function public.sync_bill_occurrences_on_bill_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.amount is distinct from old.amount then
    update public.bill_occurrences o
       set expected_amount = new.amount
     where o.bill_id = new.id and o.status = 'due' and o.paid_amount is null
       and o.due_date >= public.app_today();
  end if;

  if (old.is_active and not new.is_active)
     or new.frequency   is distinct from old.frequency
     or new.due_day     is distinct from old.due_day
     or new.anchor_date is distinct from old.anchor_date then
    delete from public.bill_occurrences o
     where o.bill_id = new.id and o.status = 'due' and o.paid_amount is null
       and o.due_date >= public.app_today()
       and not exists (select 1 from public.transactions t where t.bill_occurrence_id = o.id);
  end if;

  if new.is_active and (not old.is_active
                        or new.frequency   is distinct from old.frequency
                        or new.due_day     is distinct from old.due_day
                        or new.anchor_date is distinct from old.anchor_date) then
    perform public.ensure_bill_occurrences();
  end if;
  return new;
end;
$$;

create trigger sync_bill_occurrences
  after update of amount, is_active, frequency, due_day, anchor_date on public.bills
  for each row execute function public.sync_bill_occurrences_on_bill_change();
