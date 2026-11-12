# Spec review: what was wrong with v2 and what was built instead

**Bottom line:** As written, SPEC v2 would not have deployed. Two of its SQL definitions are
rejected by Postgres, and the category seed cannot run in a migration. Beyond that, ten
logic gaps would have produced wrong numbers with no error. The biggest are credit-card
balance signs, double-counted card payments, and a safe-to-spend that never goes down
as you spend. All of these are fixed in the migrations and covered by tests (169 pgTAP
assertions).

Confidence tags: **[Certain]** = reproduced or proven by a test, **[Likely]** = strong
inference, **[Guessing]** = judgment call.

---

## A. Blocking defects (the spec's SQL fails)

| # | Spec text | Problem | Fix |
|---|---|---|---|
| A1 | §6.3 `owner_id default (select owner_id from app_settings limit 1)` | Postgres: `cannot use subquery in DEFAULT expression`. **[Certain]**, reproduced on PG16. | `default public.app_owner_id()`: a function returning `coalesce(auth.uid(), app_settings.owner_id)`. Logged-in users and Claude's privileged writes both get the right owner. |
| A2 | §3 `fingerprint ... txn_date::text ...` generated column | Postgres: `generation expression is not immutable`. The date→text cast depends on `DateStyle`, so it is only STABLE. **[Certain]**, reproduced. | `txn_fingerprint()`: an IMMUTABLE function using `to_char(date,'YYYY-MM-DD')` and `amount::numeric(12,2)`. The output format matches what the spec intended. |
| A3 | §9 Phase 1 "seed categories" in migrations | `categories.owner_id` is NOT NULL, and no user exists when migrations run. **[Certain]** | `bootstrap_owner('you@email')`, run once after creating your Auth user. It sets `app_settings` and seeds the 17 spec categories plus "Credit Card Payment" (see B2). Idempotent. |

## B. Silent wrong-number bugs

| # | Problem | Fix |
|---|---|---|
| B1 | **Credit-card balance sign.** Banks display a card's balance as a positive amount owed, while transactions use negative = out. "Last snapshot + transactions" would make a purchase *lower* the debt. **[Certain]** | Snapshots and debt balances are stored *as displayed*. Views negate `credit_card`/`loan` balances before any math. Tested both ways in `06_balance_check`. |
| B2 | **Card payments double-counted as spending.** Card purchases are already spending; the checking→card payment (kind `debt_payment`) would count again in `v_month_spending`/`v_cash_flow`. **[Certain]** | Added the category **Credit Card Payment** (kind `transfer`, excluded). Instructions tell Claude to use it on both sides. Loan payments stay `Debt Payment`. |
| B3 | **Safe-to-spend never goes down.** The formula is a budget for the paycheck and ignores what you've spent since payday. On day 13 of 14 it shows the same number as on day 1. **[Certain]** | Kept `safe_to_spend` exactly as specified. Added `spent_so_far` (expense or uncategorized outflows since payday, not linked to a bill or debt, net of refunds) and `remaining_safe_to_spend`. The dashboard shows both. |
| B4 | **Overdue bills vanish.** Only bills due inside the period were counted, so an unpaid bill from last period dropped out of the budget. **[Certain]** | The current period carries in unpaid overdue occurrences, flagged `overdue: true` in `items`. |
| B5 | **Minimums already paid still subtracted.** **[Certain]** | A minimum is reduced by payments linked to that debt (`debt_id`) in the month before its due date, and capped at the current balance. |
| B6 | **Future pay periods show no bills.** `v_pay_periods` goes 6 periods ahead (~12 weeks for biweekly, 6 months for monthly), but occurrences only exist 60 days out. **[Certain]** | `paycheck_plan` projects due dates from the bill schedule wherever no occurrence row exists yet (`projected: true`). |
| B7 | **Undo left bills marked paid.** Deleting a batch cascades to its transactions, but the FK only nulls `bill_occurrences.transaction_id` and leaves status `paid`. **[Certain]** | A BEFORE DELETE trigger resets the occurrence to `due`. Tested in `02_import_batch_cascade`. |
| B8 | **Pending vs posted balance.** Most banks' main balance excludes pending items; some include them. Using the wrong assumption makes every balance check fail by the pending total. **[Likely]** | `accounts.balance_includes_pending` (default false). `v_balance_check` uses it and also reports `pending_between`, plus a `likely_cause` that recognizes pending timing. |
| B9 | **Paychecks-per-year.** `extra_debt = extra_monthly × 12 / paychecks per year` needs a definition when there are two income sources. A naive 365-day count also gives 27 biweekly paydays, which the test suite caught. **[Certain]** | Distinct paydays in a 364-day window: 26 / 52 / 24 / 12. Pay periods are defined by the union of all sources' paydays. |
| B10 | **"Today" was UTC.** `current_date` on Supabase is UTC, so after 7–8 pm Eastern the app thinks it's tomorrow. **[Likely]** | `app_today()` uses `app_settings.timezone` (default America/New_York) everywhere. |

## C. Gaps filled

- **`v_debts` utilization needs a credit limit**, and the schema had none. Added `debts.credit_limit`. **[Certain]**
- **Weekend paydays.** Added `income_sources.weekend_adjust`: Saturday/Sunday paydays move to Friday or Monday. Bank holidays are *not* modelled. **[Certain]**
- **One active debt plan:** enforced with a partial unique index (the spec implied it, nothing enforced it).
- **Bill changes:** changing a bill's amount updates future unpaid occurrences, and deactivating a bill removes its future unpaid ones. Paid history is untouched.
- **`v_debts` freshness:** if a card is tracked as an account and its screenshot is newer than the last `debt_balances` row, the account estimate is used (`balance_source` says which).
- **Total debt** also counts credit-card/loan accounts that have no `debts` row, so nothing is silently missing.
- **Extra views for the web app** so it never has to do math: `v_transactions`, `v_debt_balance_history`, `v_active_debt_plan`, `v_debt_plan_schedule`, `v_debt_plan_projection`, and `v_bill_match_candidates` (for Claude).

## D. The screenshot procedure is now code, not prose

SPEC §5.1 asked Claude to apply the dedupe rules (fingerprint skip, occurrence numbering,
pending→posted within ±3 days, ask on near-matches) by reading query results. That is the
error-prone part of the system, and the model would be doing it fresh on every screenshot.
It now runs in SQL:

- `preview_screenshot_import(account, rows)` is read-only and returns `skip / update / ask / insert` per row.
- `commit_screenshot_import(...)` re-runs the preview inside one transaction. It refuses unresolved `ask` rows and unknown category names, then writes the batch, rows and snapshot, sets the counts, and returns the balance check.
- `mark_bill_paid(occurrence, transaction)` links a payment to a bill as paid or partial.

Claude still reads the screenshot, picks categories, shows you the table and waits for "ok".
The Phase 2 acceptance criteria (no duplicates across overlapping screenshots, pending→posted
updates, balance check = 0) are proven in `08_screenshot_import.test.sql` against these
functions.

## E. Security hardening beyond §6

- **TRUNCATE bypasses RLS** **[Certain]**, and Supabase grants table privileges to `anon`/`authenticated` by default **[Likely]**. All table privileges are revoked, with only `SELECT` granted back to `authenticated`. `anon` has nothing. Tests prove INSERT/UPDATE/DELETE/TRUNCATE fail on every table, and that RLS still blocks writes even if someone re-grants privileges.
- **RPC exposure:** every function is callable through the REST API unless revoked. Writer functions (`commit_screenshot_import`, `mark_bill_paid`, `ensure_bill_occurrences`, `bootstrap_owner`) are not executable by API roles. **[Certain]**, tested.
- **The connector is the real risk, and the spec under-states it.** Claude's `execute_sql` runs as `postgres`, which bypasses RLS and can `DROP` anything. The "Needs approval" prompt is the only guard, and approving 5–10 prompts per screenshot leads to rubber-stamping. **[Likely]** Mitigations in the setup doc: scope the connector with `?project_ref=<ref>&features=database,docs` (confirmed in the Supabase MCP docs), keep `apply_migration` blocked, and turn on Supabase's daily backups / PITR if your plan allows. A tighter design would put Claude on a non-superuser role that can only call the procedures. The hosted Supabase MCP doesn't support choosing a role (only `read_only=true`), so this is deferred.

## F. Decisions I made instead of asking (you said not to stop)

| Item | Decision | Why |
|---|---|---|
| S5 hosting (OPEN) | Built for both. `web/vercel.json` is ready for Vercel, and `npm run dev` runs locally. Nothing is deployed, since that needs your accounts. | Zero lock-in; deploying is a 5-minute human step. |
| `v_upcoming_bills` | Includes `partial` and overdue, not just `status = 'due'` | A partially paid bill is still upcoming money out. |
| Uncategorized transactions | Count as spending (out) or income (in) in `v_cash_flow`, reported in `uncategorized_count` | Otherwise un-reviewed rows disappear from totals. |
| Bill occurrences generated from the 1st of the current month | Past months before adoption have no occurrences | Fabricating history would show bills as unpaid that you actually paid. |

## G. Known limitations (residual risk, documented, not fixed)

1. **Undoing a batch does not revert a pending→posted update it made.** The updated row belongs to the batch that first inserted it. Fixing this needs an audit/history table, which is a good Phase 4 item. **[Certain]**
2. **A bill paid but not yet matched** is counted twice in the current period: once in `bills_total` and once in `spent_so_far`, until `mark_bill_paid` links it. **[Certain]**
3. **Stale pending rows** (a hold that never posts) keep reducing the estimated balance until Claude or you remove them. **[Certain]**
4. **Pending→posted matching uses a heuristic:** same amount, ±3 days, description prefix or same first 5 characters, or same merchant rule. Two different merchants with the same amount and prefix in the same 3 days could be merged. The preview shows every `update` before anything is written. **[Likely]** rare.
5. **`likely_cause` "divisible by 9"** is a weak hint for transposed digits. Treat it as a pointer, not a diagnosis. **[Certain]**
6. **Bank holidays** are not modelled for paydays.
7. **Tests ran on plain PostgreSQL 16** with a small Supabase shim (no Docker in the build environment), not on a live Supabase PG17 instance. The SQL uses only features available in both. The files are standard pgTAP and run unchanged with `supabase test db`. **[Likely]** no differences; run that command once to confirm.
