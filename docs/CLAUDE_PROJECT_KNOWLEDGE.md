# Money Hub: reference for Claude (upload as Project knowledge)

All objects live in the `public` schema of the Supabase project **money-hub**.
`owner_id` columns fill themselves in, so never set them.

## Quoting tip
Wrap JSON in dollar quotes so apostrophes in descriptions (`MCDONALD'S`) need no
escaping: `$j$[ ... ]$j$::jsonb`.

---

## Tables you write (facts)

| Table | Key columns | Notes |
|---|---|---|
| `accounts` | name, institution, kind (`checking`/`savings`/`credit_card`/`loan`/`cash`), last4, balance_includes_pending, is_active | name is unique |
| `import_batches` | account_id, source, screenshot_range_start/end, rows_inserted, rows_updated, notes | created by `commit_screenshot_import` |
| `transactions` | account_id, import_batch_id, txn_date, description_raw, merchant, amount, status (`pending`/`posted`), category_id, tags, needs_review, review_question, occurrence, bill_occurrence_id, debt_id, note | `fingerprint` is generated; unique (account_id, fingerprint, occurrence). `posted_at`/`pending_txn_date` are set automatically when a pending row posts. Never set them yourself. |
| `balance_snapshots` | account_id, import_batch_id, as_of_date, balance, available | balance as displayed (cards/loans: owed, positive) |
| `categories` | name, parent_name, kind (`expense`/`income`/`transfer`/`debt_payment`) | add only when I ask |
| `merchant_rules` | pattern (case-insensitive substring), merchant, category_id, tags | longest matching pattern wins |
| `income_sources` | name, frequency (`weekly`/`biweekly`/`every_6_weeks`/`semimonthly`/`monthly`), anchor_date (a real payday), semimonthly_days (e.g. `{15,31}`), weekend_adjust (`none`/`previous_business_day`/`next_business_day`), expected_net, deposit_account_id | a rotating pay pattern (long/long/short) = one `every_6_weeks` source per slot |
| `pay_date_overrides` | income_source_id, scheduled_date, actual_date, actual_net, note | one-off moved/changed paycheck; actual_net null = keep expected_net, 0 = no pay; actual_date within 10 days |
| `bills` | name, amount (positive), is_variable, frequency (`weekly`/`biweekly`/`monthly`/`quarterly`/`annual`), due_day, anchor_date, end_date, debt_id, autopay, pay_from_account_id, category_id, match_pattern | monthly needs due_day; weekly/biweekly/quarterly/annual need anchor_date. end_date = last payment (installments). debt_id = this bill is that debt's payment schedule (one per debt) |
| `bill_occurrences` | bill_id, due_date, expected_amount, paid_amount, paid_date, status (`due`/`paid`/`partial`/`skipped`), transaction_id | created by `ensure_bill_occurrences()` (daily cron) |
| `debts` | name, kind, account_id (if a tracked card/loan account), apr (24.990 = 24.99%), min_payment, due_day, credit_limit, promo_apr, promo_ends | min_payment changes flow to the linked bill's amount |
| `debt_balances` | debt_id, as_of_date, balance (owed, positive), import_batch_id | insert only, never overwrite |
| `set_asides` | name, per_paycheck, cap, start_date, opening_balance, category_id, is_active | Rollover set-aside (not an envelope). Write only through `create_set_aside` / `update_set_aside` (templates below); pause, never delete: +per_paycheck each payday (stops at cap; null cap = unlimited). Spending draws it down when `transactions.set_aside_id` is set, or (untagged) the txn's category = `category_id`. Balance is derived, never stored. Drawn spending is not counted as discretionary |
| `envelopes`, `envelope_moves` | kind (`rainy_day`/`locked_savings`/`goal`), name, is_active; moves: envelope_id, move_date, amount (+ in, − out), note | "Envelope" means only these virtual savings pots: the rainy-day fund, locked savings, and goal envelopes (user-named, any number). Not set-asides. No real money moves. Write only through functions: `create_envelope(name)`, `update_envelope(id, name, is_active)` (goal only; archive needs balance 0), `move_envelope_money(envelope_id, amount, note)` (refuses a move in that would make envelopes plus set-aside balances exceed real cash). The forecast subtracts every active envelope from starting cash; only the rainy-day fund is ever suggested as a draw |
| `debt_plans` | name, strategy, extra_monthly, assumptions, summary, schedule, balances_as_of, is_active | only one active |
| `app_settings` | owner_id, timezone, low_balance_threshold, stale_after_days | one row |

## Views and functions you read (math)

| Name | What it gives you |
|---|---|
| `v_dashboard` | one row: today, total_cash, total_debt, net, bills_due_7d_count/total, overdue_bills_count/total, next_payday(+amount), period_start/end, safe_to_spend, spent_so_far, remaining_safe_to_spend, shortfall, review_queue_count, oldest_data_days, accounts_without_snapshot, balance_check_issues, low_balance_accounts |
| `v_account_balances` | per account: last_snapshot_balance/date, transactions_since_snapshot, pending_total, estimated_balance (signed), estimated_balance_display (as the bank shows it), days_since_screenshot, is_low_balance |
| `v_balance_check` | per snapshot after the first: expected_balance, actual_balance, difference, pending_between, likely_cause, is_latest |
| `v_transactions` | transactions joined to account and category |
| `v_review_queue` | v_transactions where needs_review |
| `v_month_spending` | month × category: total_out, total_in, net, txn_count (transfers excluded) |
| `v_cash_flow` | month: income, spending, net, uncategorized_count |
| `v_bill_status` | occurrences: bill_name, due_date, due_month, expected/paid/remaining_amount, status, days_until_due, overdue, debt_id, end_date |
| `v_upcoming_bills` | unpaid occurrences due within 30 days, overdue included |
| `v_monthly_bills_total` | monthly_total, autopay_monthly_total, variable_monthly_total, active_bill_count |
| `v_debts` | balance, balance_as_of, balance_source, effective_apr, min_payment, next_due_date, utilization_pct, payment_bill_id, final_payment_date, overdue_amount |
| `v_bill_match_candidates` | unmatched outflows that look like a bill payment (use rank = 1) |
| `v_bill_month_totals` | per due_month: expected_total, paid_total, remaining_total, counts |
| `v_app_info` | today (owner's time zone), current_month, timezone, stale_after_days |
| `v_pay_periods` | period_offset −2…+6 with every paycheck_plan column |
| `v_set_asides` | set-asides with balance (rollover, can be negative if overspent), cap, room_left, at_cap, current_contribution |
| `v_pay_period_forecast` / `pay_period_forecast(periods, lookahead)` | per period from today: safe_to_spend (levelized, covers short paychecks and bill clusters), max_safe_to_spend, hold_for_later (+ = keep back, − = uses earlier holds), carry_out, binding_date, shortfall. Anchored to real cash; a paycheck counts once its deposit transaction is imported |
| `v_debt_balance_history`, `v_active_debt_plan`, `v_debt_plan_schedule`, `v_debt_plan_projection` | debt charts |
| `pay_dates(start, end)` | paydays for active income sources |
| `paycheck_plan(date default today)` | period_start/end, expected_net, bills_total, minimums_total, set_asides_total, extra_debt, safe_to_spend, shortfall, spent_so_far, remaining_safe_to_spend, items (jsonb, itemized) |
| `match_merchant_rule(description)` | best rule for a description |

---

## SQL templates

### Screenshot: preview (read-only)
```sql
select row_num, txn_date, description_raw, amount, status, action, insert_occurrence,
       existing_txn_date, existing_description, existing_status, reason,
       suggested_merchant, suggested_category
from preview_screenshot_import(
  '<account_id>',
  $j$[
    {"txn_date":"2026-03-02","description_raw":"KROGER #123","amount":-45.10},
    {"txn_date":"2026-03-05","description_raw":"SQ *JOES COFFEE","amount":-12.00,"status":"pending"}
  ]$j$::jsonb);
```
`status` defaults to `posted`. Keep the rows in the order they appear on screen.

### Screenshot: commit (after the user says ok)
```sql
select commit_screenshot_import(
  p_account_id  => '<account_id>',
  p_rows        => $j$[
    {"txn_date":"2026-03-02","description_raw":"KROGER #123","amount":-45.10},
    {"txn_date":"2026-03-04","description_raw":"VENMO PAYMENT","amount":-20.00,
     "category":"Misc","needs_review":true,"review_question":"Who was this Venmo to?"},
    {"txn_date":"2026-03-07","description_raw":"SHELL SERVICE STATION","amount":-40.00,
     "resolution":"insert","category":"Gas"}
  ]$j$::jsonb,
  p_balance     => 1865.41,      -- as displayed (cards: amount owed, positive)
  p_available   => null,
  p_as_of_date  => '2026-03-08',
  p_notes       => 'Chase app screenshot');
```
Optional keys per row: `merchant`, `category` (an existing name), `tags` (array), `needs_review`,
`review_question`, `note`, `debt_id`, `resolution` (`insert`/`skip`, required on `ask` rows).
Pass the SAME rows you previewed. The commit re-runs the preview inside its transaction.

### Bill matches for a batch
```sql
select transaction_id, txn_date, description_raw, amount, bill_name, due_date,
       expected_amount, would_be_paid_in_full
from v_bill_match_candidates where import_batch_id = '<batch_id>' and rank = 1;

select mark_bill_paid('<occurrence_id>', '<transaction_id>');
```
`mark_bill_paid` can be called once per payment. Several partial payments add up, and calling it
twice for the same pair changes nothing. If a bill was paid some way you can't see (cash, an
untracked account), set it explicitly instead:
`update bill_occurrences set status = 'paid', paid_date = '<date>' where id = '<occurrence_id>';`
or `status = 'skipped'` for a month that doesn't apply.

### Answering a review question
```sql
update transactions
   set category_id = (select id from categories where name = 'Dining'),
       merchant = 'Joe''s Coffee', needs_review = false, review_question = null
 where id = '<transaction_id>';

insert into merchant_rules (pattern, merchant, category_id)
values ('JOES COFFEE', 'Joe''s Coffee', (select id from categories where name = 'Dining'));
```

### Undo a batch
```sql
select (select count(*) from transactions where import_batch_id = '<batch_id>') as transactions,
       (select count(*) from balance_snapshots where import_batch_id = '<batch_id>') as snapshots,
       (select count(*) from debt_balances where import_batch_id = '<batch_id>') as debt_balances;
-- after the user confirms:
delete from import_batches where id = '<batch_id>';
```
Deleting a batch also recomputes any bill its transactions paid (back to `due`, or `partial` if
another payment remains).

### Setup by chat (examples)
```sql
insert into accounts (name, institution, kind, last4) values ('Checking', 'Chase', 'checking', '1234');

insert into income_sources (name, frequency, anchor_date, expected_net, deposit_account_id, weekend_adjust)
values ('Paycheck', 'biweekly', '2026-03-06', 2450.00,
        (select id from accounts where name = 'Checking'), 'previous_business_day');

insert into bills (name, amount, frequency, due_day, autopay, pay_from_account_id, category_id, match_pattern)
values ('Rent', 1450, 'monthly', 1, false, (select id from accounts where name = 'Checking'),
        (select id from categories where name = 'Housing'), 'RENT');
select ensure_bill_occurrences();

insert into debts (name, kind, account_id, apr, min_payment, due_day, credit_limit)
values ('Visa', 'credit_card', (select id from accounts where name = 'Visa'), 24.99, 40, 15, 5000);
insert into debt_balances (debt_id, as_of_date, balance)
values ((select id from debts where name = 'Visa'), '2026-03-01', 1840.66);

-- Set-asides: always through these functions (they validate; never insert/update set_asides directly).
-- create_set_aside(name, per_paycheck, cap, start_date, opening_balance, category_id); nulls = no cap / today / 0 / none
select public.create_set_aside('Christmas gifts', 40);
-- Rollover set-aside with a cap, drawing from a category:
select public.create_set_aside('Car & fuel', 50, 350, null, 0, (select id from categories where name = 'Gas'));
-- Edit or pause (pass every field; is_active false = paused, never delete):
select public.update_set_aside(sa.id, sa.name, 60, sa.cap, sa.start_date, sa.opening_balance, sa.category_id, true)
  from set_asides sa where sa.name = 'Car & fuel';
-- Tag one-off spending to a set-aside:
update transactions set set_aside_id = (select id from set_asides where name = 'Car & fuel') where id = '...';
```

### Save a debt plan ("save this plan")
```sql
update debt_plans set is_active = false where is_active;   -- only if activating
insert into debt_plans (name, strategy, extra_monthly, assumptions, summary, schedule, balances_as_of, is_active)
values ('Avalanche +$200', 'avalanche', 200,
  $j${"start_month":"2026-04","new_charges":"assumed to stop","apr_changes":"none"}$j$::jsonb,
  $j${"debt_free_month":"2028-07","total_interest":4312.55,
      "payoff":{"<debt_id>":"2026-11"}}$j$::jsonb,
  $j$[{"month":"2026-04","debt_id":"<debt_id>","start":1840.66,"interest":38.33,"payment":240.00,"end":1638.99}]$j$::jsonb,
  '2026-03-09', true);
```
`schedule` must be a JSON array of `{month:"YYYY-MM", debt_id, start, interest, payment, end, minimum}`
(the web app charts it). `minimum` = the part of `payment` that is the scheduled minimum; paycheck_plan()
budgets `payment - minimum` (rollover + extra) for each month via `debt_plan_extra_for_month()`.
Without `minimum` keys the plan falls back to a flat `extra_monthly`.
