# Money Hub — MVP Spec v2 (Supabase + Claude Project + read-only web app)

> **Status:** this is the original v2 spec as handed to Claude Code, kept for reference.
> The implementation follows it, with corrections and additions recorded in
> **[docs/SPEC_REVIEW.md](docs/SPEC_REVIEW.md)**. Where the two differ, the review doc
> and the migrations in `supabase/migrations/` describe what was built. The Claude
> Project instructions in §7 have been superseded by
> **[docs/CLAUDE_PROJECT_INSTRUCTIONS.md](docs/CLAUDE_PROJECT_INSTRUCTIONS.md)**.

---

## 1. How it works

```
 iPhone / Desktop                                   Browser
 ┌──────────────────────────┐                ┌───────────────────────┐
 │ Claude Project "Money"   │                │ Web app (React/Vite)  │
 │  - screenshot in         │                │  READ-ONLY            │
 │  - reads/writes Supabase │                │  reads views only     │
 │    via Supabase connector│                │  Supabase Auth login  │
 └────────────┬─────────────┘                └──────────┬────────────┘
              │ SQL (insert/update/select)              │ select (RLS)
              ▼                                         ▼
        ┌───────────────────────────────────────────────────────┐
        │ Supabase project "money-hub"  ← SOURCE OF TRUTH         │
        │  tables (raw facts) → views/functions (all the math)    │
        │  pg_cron: create next month's bill rows                 │
        └───────────────────────────────────────────────────────┘
```

Principles:
1. **Supabase is the only source of truth.** Claude never relies on chat memory for data. It queries Supabase every time.
2. **Tables hold facts and views do the math.** Totals, safe-to-spend, bill status, and balances come from SQL views and functions. Claude reads the same numbers the web app shows, so the two never disagree.
3. **Claude writes facts only.** These are transactions, balances seen in screenshots, payments matched to bills, categories, and debt balances. It never writes computed totals.
4. **Every Claude write belongs to an `import_batch`,** so any mistake can be undone by deleting one batch.
5. **The web app only reads.** It has no inserts, no updates, and no math beyond formatting.

---

## 2. Setup decisions

| # | Item | Decision |
|---|------|----------|
| S1 | Supabase project | **New, dedicated project** for finances only. Keep it separate from TGK. |
| S2 | Claude connector | Supabase connector, scoped to this project if possible (custom connector URL with `project_ref`). In connector settings, set `execute_sql` and `apply_migration` to **Needs approval**. |
| S3 | Claude Project | One Project named "Money". All finance chats happen there. Instructions are in section 7. |
| S4 | Code execution | Turn **on** in Claude settings so forecasts and debt plans are computed with code, not mental math. |
| S5 | Web app | React + TypeScript + Vite + Tailwind + Recharts, Supabase Auth magic link, hosted on Vercel or run locally. **OPEN** |
| S6 | Money type | `numeric(12,2)` everywhere. **Sign convention: negative = money out, positive = money in** (matches how most bank apps display). |

---

## 3. Schema (tables = facts)

Every table: `id uuid primary key default gen_random_uuid()`, `owner_id uuid not null default auth.uid()` (set to the owner's user id for Claude's writes, see 6.3), `created_at timestamptz default now()`, `updated_at timestamptz default now()`.

```sql
-- Accounts you track by screenshot
create table accounts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  name text not null,                 -- "Checking", "Visa"
  institution text,
  kind text not null check (kind in ('checking','savings','credit_card','loan','cash')),
  last4 text,
  is_active boolean not null default true,
  created_at timestamptz default now(), updated_at timestamptz default now()
);

-- One row per screenshot/chat import. Undo = delete the batch (cascades).
create table import_batches (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  account_id uuid references accounts(id),
  source text not null default 'screenshot' check (source in ('screenshot','manual','chat')),
  screenshot_range_start date,        -- earliest date visible in screenshot
  screenshot_range_end date,          -- latest date visible
  rows_inserted int not null default 0,
  rows_updated int not null default 0,
  notes text,
  created_at timestamptz default now()
);

create table categories (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  name text not null,
  parent_name text,                   -- optional grouping, e.g. "Housing"
  kind text not null check (kind in ('expense','income','transfer','debt_payment')),
  unique (owner_id, name)
);

create table transactions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  account_id uuid not null references accounts(id),
  import_batch_id uuid references import_batches(id) on delete cascade,
  txn_date date not null,
  description_raw text not null,      -- exactly as shown in the screenshot
  merchant text,                      -- cleaned name, e.g. "Kroger"
  amount numeric(12,2) not null,      -- negative = out, positive = in
  status text not null default 'posted' check (status in ('pending','posted')),
  category_id uuid references categories(id),
  tags text[] not null default '{}',
  needs_review boolean not null default false,
  review_question text,               -- what Claude was unsure about
  fingerprint text generated always as (
    account_id::text || '|' || txn_date::text || '|' || amount::text || '|' ||
    lower(regexp_replace(description_raw, '[^a-zA-Z0-9]', '', 'g'))
  ) stored,
  occurrence int not null default 1,  -- 2 for a second identical txn same day
  bill_occurrence_id uuid,            -- set when matched to a bill (fk added below)
  debt_id uuid,                       -- set when it's a debt payment (fk added below)
  note text,
  created_at timestamptz default now(), updated_at timestamptz default now(),
  unique (account_id, fingerprint, occurrence)
);

-- Balance shown in each screenshot (the misread/missed-transaction check)
create table balance_snapshots (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  account_id uuid not null references accounts(id),
  import_batch_id uuid references import_batches(id) on delete cascade,
  as_of_date date not null,
  balance numeric(12,2) not null,     -- as displayed by the bank
  available numeric(12,2),
  created_at timestamptz default now()
);

create table merchant_rules (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  pattern text not null,              -- case-insensitive substring of description_raw
  merchant text,
  category_id uuid references categories(id),
  tags text[] not null default '{}',
  unique (owner_id, pattern)
);

create table income_sources (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  name text not null,
  frequency text not null check (frequency in ('weekly','biweekly','semimonthly','monthly')),
  anchor_date date not null,          -- any real past payday
  semimonthly_days int[],             -- e.g. {15,30} when semimonthly
  expected_net numeric(12,2) not null,
  deposit_account_id uuid references accounts(id),
  is_active boolean not null default true
);

create table bills (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  name text not null,
  amount numeric(12,2) not null,      -- expected, positive number
  is_variable boolean not null default false,
  frequency text not null check (frequency in ('weekly','biweekly','monthly','quarterly','annual')),
  due_day int,                        -- for monthly/quarterly/annual; 31 = last day
  anchor_date date,                   -- for weekly/biweekly, and month for quarterly/annual
  autopay boolean not null default false,
  pay_from_account_id uuid references accounts(id),
  category_id uuid references categories(id),
  match_pattern text,                 -- substring that identifies its payment
  is_active boolean not null default true
);

-- One row per bill per due date. Holds paid/unpaid history.
create table bill_occurrences (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  bill_id uuid not null references bills(id) on delete cascade,
  due_date date not null,
  expected_amount numeric(12,2) not null,
  paid_amount numeric(12,2),
  paid_date date,
  status text not null default 'due' check (status in ('due','paid','partial','skipped')),
  transaction_id uuid references transactions(id) on delete set null,
  unique (bill_id, due_date)
);

create table debts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  name text not null,
  kind text not null check (kind in ('credit_card','auto','student','personal','medical','mortgage','other')),
  account_id uuid references accounts(id),
  apr numeric(6,3) not null,          -- 24.990 = 24.99%
  min_payment numeric(12,2) not null,
  due_day int,
  promo_apr numeric(6,3),
  promo_ends date,
  is_active boolean not null default true
);

-- Balance history per debt (from statements/screenshots/chat)
create table debt_balances (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  debt_id uuid not null references debts(id) on delete cascade,
  import_batch_id uuid references import_batches(id) on delete cascade,
  as_of_date date not null,
  balance numeric(12,2) not null
);

-- Savings goals / per-paycheck set-asides
create table set_asides (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  name text not null,                 -- "Emergency fund", "Buffer"
  per_paycheck numeric(12,2) not null,
  is_active boolean not null default true
);

-- Debt payoff plans Claude computes and saves (simulator function is Phase 4)
create table debt_plans (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  name text not null,
  strategy text not null check (strategy in ('avalanche','snowball','custom','minimums_only')),
  extra_monthly numeric(12,2) not null default 0,
  assumptions jsonb not null,         -- lump sums, apr changes, order, start date
  summary jsonb not null,             -- debt-free date, total interest, per-debt payoff dates
  schedule jsonb not null,            -- [{month, debt_id, start, interest, payment, end}]
  balances_as_of date not null,       -- date of the debt_balances used
  is_active boolean not null default false,
  created_at timestamptz default now()
);

alter table transactions
  add constraint fk_bill_occ foreign key (bill_occurrence_id) references bill_occurrences(id) on delete set null,
  add constraint fk_debt foreign key (debt_id) references debts(id) on delete set null;
```

Indexes: `transactions(account_id, txn_date)`, `transactions(needs_review) where needs_review`, `bill_occurrences(due_date)`, `balance_snapshots(account_id, as_of_date desc)`, `debt_balances(debt_id, as_of_date desc)`.

Trigger: `updated_at = now()` on update, for every table that has the column.

---

## 4. Views and functions (all the math)

The web app reads **only** these. Claude uses them for every number it reports.

| Name | Returns |
|------|---------|
| `v_account_balances` | Per account: last snapshot balance + date, sum of transactions after that date, **estimated current balance**, days since last screenshot. |
| `v_balance_check` | Per snapshot after the first: previous snapshot balance + transactions between the two dates vs the new snapshot balance → `difference`. **Non-zero means a misread or missed transaction.** |
| `v_month_spending` | Per month × category: total out, total in, transaction count. Excludes `transfer` kind. |
| `v_cash_flow` | Per month: income, spending, net. |
| `v_bill_status` | Each `bill_occurrence` with bill name, due date, expected vs paid, status, days until due, `overdue` flag. |
| `v_upcoming_bills` | `v_bill_status` where status = 'due' and due within 30 days. |
| `v_monthly_bills_total` | Sum of active bills normalized to a monthly amount (weekly × 52/12, biweekly × 26/12, quarterly ÷ 3, annual ÷ 12). |
| `v_debts` | Each debt with latest balance + as-of date, APR, minimum, utilization (if credit card account known). |
| `v_review_queue` | Transactions where `needs_review` = true. |
| `v_dashboard` | One row: total cash, total debt, net (cash − debt), bills due next 7 days (count, sum), next payday, safe-to-spend for current pay period, review queue count, oldest data age. |

Functions:

- `pay_dates(p_start date, p_end date) returns table(income_source_id uuid, pay_date date, expected_net numeric)` generates paydays from each active income source's frequency + anchor. Biweekly is a `generate_series` stepping 14 days from `anchor_date`. Semimonthly uses `semimonthly_days`, and a day greater than the month's last day uses the last day.
- `paycheck_plan(p_pay_date date default null) returns table(...)` defaults to the current pay period, which runs from the latest payday ≤ today to the next payday. It returns:
  - `expected_net` for the period's paycheck(s)
  - bills with a `bill_occurrence` due in `[pay_date, next_pay_date)` and status ≠ paid
  - debt minimums with `due_day` in that window
  - `set_asides` per paycheck
  - `extra_debt` = active `debt_plans.extra_monthly` × 12 / paychecks per year
  - **`safe_to_spend` = expected_net − unpaid bills − minimums − set-asides − extra_debt**
  - `shortfall` boolean if negative
- `v_pay_periods` (view over `pay_dates` for −2 to +6 periods) feeds the web app's paycheck timeline, with `safe_to_spend` per period.
- `ensure_bill_occurrences(p_through date default (current_date + 60)) returns int` creates any missing `bill_occurrences` up to the given date. It's idempotent via the unique (bill_id, due_date) constraint. Clamp `due_day` 29–31 to the month's last day.
- `pg_cron`: run `ensure_bill_occurrences()` daily at 05:00. **This is the only scheduled job.**

---

## 5. Claude's write procedures (enforced by Project instructions, section 7)

### 5.1 Logging a screenshot
1. Identify the account (ask if unclear). Read every visible transaction: date, description as shown, amount with sign, and pending vs posted. Read the **balance shown**.
2. Create an `import_batch` with the visible date range.
3. **Duplicate check, against Supabase and not chat history:** query `transactions` for that account where `txn_date` is between range_start − 3 days and range_end.
   - Exact fingerprint already present → skip. If the screenshot shows the same fingerprint more times than the DB has, insert the extra with `occurrence` = next number.
   - A **pending** row in the DB with the same amount within ±3 days whose cleaned description matches or starts with the same merchant, when the screenshot shows it posted → **update** that row to `posted` with the new date and description. Don't insert.
   - Same amount, date within ±3 days, but a different description → **ask** before inserting.
4. For new rows, apply `merchant_rules` first. If no rule matches, pick a category from `categories`. If unsure, insert with `needs_review = true` and a `review_question`, and ask at the end.
5. **Show a table of what will be inserted, updated, or skipped, and wait for confirmation** before writing.
6. Write the rows, set batch counts, and insert a `balance_snapshot` from the displayed balance.
7. Query `v_balance_check` for this account. If `difference` ≠ 0, tell me the amount and the likely cause (missed row, misread digit, pending timing).
8. Match bill payments: for new outflows matching a bill's `match_pattern` near a `due` occurrence, set the occurrence to `paid` (or `partial`) and link the transaction. Confirm in the summary.
9. When I answer a review question, update the transaction, and **offer to save a `merchant_rule`** so the question doesn't come back.

### 5.2 Other writes
- Bills, income, debts, set-asides, and categories change only when I ask. Claude restates the change and confirms before writing.
- Debt balances: insert a new `debt_balances` row and never overwrite history.
- Never run `DELETE` except deleting an `import_batch` I name. Never alter schema from chat; schema changes go through Claude Code migrations.

### 5.3 Forecasts and debt plans
- Pull inputs from `v_debts`, `v_monthly_bills_total`, `pay_dates()`, and `paycheck_plan()`.
- Compute with **code execution**, never in your head. Use a monthly loop: interest = balance × APR/12, pay minimums, apply extra plus rollover from paid-off debts by strategy order, and stop when payment < interest (flag "never pays off").
- State assumptions: start date, balances as-of date, APRs, and whether new charges are assumed to stop.
- Save to `debt_plans` only when I say "save this plan". Setting one `is_active` feeds `paycheck_plan()`.

---

## 6. Security

### 6.1 Supabase
- RLS **enabled on every table**.
- Policy for `authenticated`: `select` where `owner_id = auth.uid()`. **No insert, update, or delete policies** for `authenticated` or `anon`, so the web app physically can't write.
- Views: create with `security_invoker = true` so RLS applies through them. `pay_dates` / `paycheck_plan` are `security invoker` too.
- Sign-ups disabled in Supabase Auth. Create one user (you) manually.

### 6.2 Claude connector
- Dedicated project, tools that write set to Needs approval, and no other projects reachable if scoping works.

### 6.3 `owner_id` for Claude's writes
Claude's SQL runs as a privileged role, so `auth.uid()` is null. Store the owner's user id in a one-row table `app_settings(owner_id uuid, timezone text default 'America/New_York', low_balance_threshold numeric)`, and set the column default to `(select owner_id from app_settings limit 1)` instead of `auth.uid()`.

---

## 7. Claude Project instructions

**Superseded — use [docs/CLAUDE_PROJECT_INSTRUCTIONS.md](docs/CLAUDE_PROJECT_INSTRUCTIONS.md).**
The original text called for Claude to run the dedupe logic by hand; the implementation
provides `preview_screenshot_import()` / `commit_screenshot_import()` so the rules in §5.1
run as tested SQL instead.

---

## 8. Web app (read-only)

Pages (mobile-first):
1. **Dashboard:** `v_dashboard` cards, 7-day upcoming bills, safe-to-spend, "data is N days old" warning, review queue count.
2. **Transactions:** table from `transactions` joined to categories, with filters for month, category, account, and tag. Rows with `needs_review` are highlighted.
3. **Bills:** month calendar + list from `v_bill_status` (paid/due/overdue colors) and the monthly total from `v_monthly_bills_total`.
4. **Paychecks:** timeline from `v_pay_periods`. Each card lists the bills covered, minimums, set-asides, extra debt, and safe-to-spend.
5. **Spending:** charts from `v_month_spending` and `v_cash_flow`.
6. **Debts:** `v_debts` table + balance history chart from `debt_balances` + the active `debt_plans` schedule as a projected line.

Rules: `@supabase/supabase-js` with the anon key + logged-in session; `select` only; no client-side math beyond formatting and chart scaling; empty and error states for every view.

---

## 9. Build phases

**Phase 1: Database** (Claude Code, migrations)
Tables, indexes, triggers, `app_settings`, views, functions, `pg_cron` job, RLS, seed categories (Housing, Utilities, Groceries, Dining, Gas, Auto, Insurance, Phone/Internet, Subscriptions, Medical, Kids, Shopping, Entertainment, Debt Payment, Transfer, Income, Misc).
*Accept (SQL tests):*
- Inserting the same fingerprint twice with the same `occurrence` fails, and `occurrence = 2` succeeds.
- Deleting an `import_batch` removes its transactions and snapshots.
- `pay_dates` returns correct biweekly dates and 3-paycheck months, and semimonthly handles month-end.
- `ensure_bill_occurrences` is idempotent and clamps the 31st to Feb 28/29.
- `paycheck_plan` matches a hand-computed example, including a shortfall case.
- `v_balance_check` shows 0 for consistent data and the right difference for a missing row.
- As an `authenticated` user, insert/update/delete all fail and select returns only owned rows.

**Phase 2: Claude Project**
Create the Project, paste the section 7 instructions, connect Supabase (scoped, approvals on), enter accounts, bills, income, debts, and set-asides by chat.
*Accept:* two overlapping screenshots in a row produce zero duplicates, a pending→posted change updates instead of inserting, and the balance check reports 0.

**Phase 3: Web app**
Pages in section 8.
*Accept:* every number on screen matches the same view queried in the Supabase SQL editor, and the web app cannot write (verified from the browser console).

**Phase 4: Back burner**
`simulate_payoff(...)` Postgres function (so the web app can have sliders), CSV import as an alternative to screenshots, and household access for a second user.
