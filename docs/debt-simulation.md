# Read-only debt simulation

`public.simulate_debt_plan(p_params jsonb default '{}') -> jsonb` returns
`{schedule, summary}`. It is `STABLE`, uses a fixed empty search path, checks
`assert_app_owner()`, and never writes tables. An authenticated owner and an active
plan are required. Anonymous callers and other users cannot execute it. The
private calculation helper is inaccessible to application roles.

Simulations never save or activate plans. The web app's **What if** page (`/what-if`,
linked from Debts) is the UI for this RPC and calls it through `web/src/lib/reads.ts`.

`20261113070000_debt_scenario_affordability.sql` decorates the result with
`monthly_balances`, `defaults` and `affordability` (below). Installed in production on
November 13, 2026; Supabase recorded apply version `20261113162900` under the name
`debt_scenario_affordability`. Before/after checks left `v_dashboard`, the current
`v_pay_period_forecast` row and the counts of debts (18), balance records (27) and plans (3)
unchanged. Without it the What if page shows "The scenario database update has not been
installed yet." Covered by `18_debt_scenario_affordability.test.sql`.

Installed in Money Hub production on November 13, 2026, from
`20261113060000_simulate_debt_plan.sql`; Supabase recorded apply version
`20261113055912` under the name `simulate_debt_plan`. The live read-only call
matches the results below, and explicit zero equals the minimums-only schedule.
Before/after checks preserved all 18 debts, 27 balance records, and three plans,
including their content hashes. Dashboard and forecast rows were unchanged:
cash $2,049.33 and current forecast safe-to-spend $0.10 before and after.

## Inputs

```sql
select public.simulate_debt_plan('{}');
select public.simulate_debt_plan('{
  "strategy": "custom",
  "custom": ["e4087555-07b4-4141-95fb-d5b7ab8db92e"],
  "extra_monthly": 100,
  "lump_sums": [{"date":"2027-02-15","amount":500,"target_debt_id":null}],
  "payoff_now": [],
  "drop_payment": [{"label":"SoFi $10 fee","from_month":"2027-01"}],
  "raise": {"effective_date":"2027-01-15","extra_net_per_paycheck":50},
  "overtime": [{"pay_date":"2026-12-15","hours":8}],
  "apr_overrides": {"e4087555-07b4-4141-95fb-d5b7ab8db92e":9.99}
}');
```

- Strategy: `avalanche`, `snowball`, or `custom` with a `custom` array of debt IDs.
  Unlisted custom debts follow APR descending. UUID breaks ties deterministically.
  `minimums_only` is also supported for the baseline sanity check.
- Omitted strategy and extra inherit the active plan. Structured scenario inputs
  in its `assumptions` supply other defaults; explicit inputs replace entire
  arrays/maps. Prose assumptions are never parsed as instructions.
- **Explicit `extra_monthly: 0` disables rollover.** Omitted extra preserves the
  active plan's rollover even when its extra is zero. This distinction reconciles
  the requested golden default (zero extra WITH rollover) and zero-extra sanity
  check (minimums-only). Use `{}` for the existing avalanche-and-rollover plan.
- Lump sums reduce balances at the start of their calendar month, before interest.
  A target receives cash first; excess joins the strategy pool. Untargeted cash
  follows strategy after minimums. Dates before the simulation month are rejected.
- `payoff_now` uses starting-month lump cash first. Any unfunded remainder is
  explicitly `what_if_removed`, never counted as a cash payment or silently funded
  with future lump sums. It takes effect in the first simulated month. Freed
  minimums become available the following month.
- `drop_payment` with a debt ID stops that debt's minimum and redirects its budget;
  it **does not erase the balance or stop interest**. A label must uniquely match
  an active monthly standalone bill, whose amount is redirected. `SoFi $10 fee`,
  `SoFi fee`, and `SoFi monthly fee` stop the capitalized fee; they do not also
  invent $10 cash. Effective month is inclusive. Duplicate drops are rejected.
- Raises count actual `pay_dates()` entries on/after the effective date, including
  date overrides, for all active owner income sources. With multiple jobs this
  means the raise applies to every paycheck. No assumed two-check multiplier.
- Overtime adds `hours * app_settings.extra_hour_net` in its pay month.
- APR overrides are percentages (`9.99`, not `.0999`). Affirm principal is valued
  using the stored contractual APR **before** applying a hypothetical APR change.

## Calculation conventions

Balances come directly from `debt_balances`, ordered by `as_of_date DESC,
created_at DESC, id DESC`, scoped to the owner. No account-snapshot substitutions.
Missing balances/minimums and unsupported frequencies fail explicitly.

The start month is the active plan's `balances_as_of` month. The stored November
2026 schedule supplies the remaining payments, including LoveSac's returned
payment retry. Ally's December extension minimum comes from that schedule.
All subsequent monthly minimums use current debt records. Interest begins in
December 2026 and is rounded to cents monthly: `balance * APR / 1200`.
SoFi uses 22.74% plus a capitalized $10 fee; GoodLeap uses 11.49%. Explicit APR
overrides take precedence. Home Depot uses its stored blended APR, with no buckets.

All minimums are paid before strategy extras. A retired debt's full minimum rolls
over starting **the next month**. Unused final minimums do not transfer in the payoff
month; surplus extra cash can continue to another target that same month. Zero-APR
debts stay on minimums regardless of strategy, except an explicit targeted lump or
`payoff_now`. Unallocated extra is reported as `unused_cash`; it is not banked.

Affirm frequencies were verified from the linked bills: all nine are monthly.
The function rechecks this every call. For each loan, `n = ceil(balance / minimum)`;
principal is the PV of `n-1` full minimums plus the actual remaining final installment,
at the stored APR / 12. Discounting a full final minimum would invent principal
when the final payment is smaller. This keeps every loan payable on its scheduled
minimum and lets avalanche extra reduce interest. The monthly model deliberately
charges no November interest, including Affirm; it is an approximation, not a
lender payoff quote.

Simulation stops at payoff or 1,200 months. Non-payoff returns `completed: false`,
null payoff date/month savings/interest savings, and outstanding balances. Interest
and payments in that case are only amounts simulated within the horizon.

## Returned values

Schedule rows contain `month`, `debt_id`, `start`, `interest`, `fee`, `minimum`,
`payment`, `what_if_removed`, and `end`. Every row balances:
`start + interest + fee - payment - what_if_removed = end`.

Summary includes the requested interest, debt-free month, payoff order and
per-debt payoff months, interest savings and months saved against an independently
computed minimums-only baseline using original APRs and no scenario changes.
`total_fees` and `total_interest_and_fees` keep fees distinguishable from interest.
It also includes derived Affirm principals, total payments, unfunded what-if
removals, remaining balances, completion status, and legacy comparison figures.
Payoff ties within a month are listed by UUID, not an invented intramonth order.

## Golden regression and measured gap

The first two assertions in `17_simulate_debt_plan.test.sql` independently recompute
historical behavior from the November 12 statement-verified fixture. A hard gate
prevents subsequent scenario tests if that reproduction fails.

| Measure | Historical model | Corrected Affirm model |
| --- | ---: | ---: |
| Debt-free month | 2029-10 | 2029-10 |
| Interest plus fees | $10,489.51 | $11,069.44 |
| Separately reported interest | not separated in saved summary | $10,829.44 |
| SoFi fees | included above | $240.00 |
| Starting modeled principal | $55,825.68 | $55,026.99 |
| Total cash payments | $66,315.19 | $66,096.43 |

Historical reproduction matches **exactly**, within the requested $1 tolerance.
The corrected default is not falsely asserted to have identical interest: the old
model counted $798.69 of embedded future Affirm interest as opening debt, then
reported zero Affirm interest. The new model removes that amount from principal
and reports actual simulated Affirm interest. Financing charges increase $579.93
on the now-comparable interest-plus-fees line, while total payments decrease
**$218.76**. Both models finish in October 2029. The RPC reports both figures and
this accounting distinction; it does not return the stored schedule as a simulation.

| Affirm loan | Stored remaining payments | Derived principal |
| --- | ---: | ---: |
| Alls | $82.45 | $75.55 |
| Amazon (13th) | $69.40 | $63.72 |
| Amazon (7th) | $92.91 | $85.92 |
| Crown | $1,254.98 | $968.52 |
| farmgirlflowers | $49.90 | $46.63 |
| Mattress | $1,630.02 | $1,417.22 |
| Nintendo | $63.51 | $59.05 |
| PIPER-JOINPOLLY | $1,358.99 | $1,088.22 |
| Whatnot | $31.66 | $30.30 |

These are fixture results, not persisted changes to the debts. Re-running against
new balances, rates, or plan data will produce different results.

Tests run using the repository's pgTAP suite (`supabase test db` after local
migrations, or `scripts/test-db-local.sh` with its prerequisites). They cover all
inputs, golden compatibility, same-day balance selection, rollover, zero-APR
minimums, money conservation, ownership, permissions, and a read-only transaction.

## Scenario context (migration 20261113070000)

The migration keeps `{schedule, summary}` unchanged and adds three keys. All arithmetic stays
in PostgreSQL; the browser only displays these values.

- `monthly_balances`: per month, the sums of the schedule's `start` (`opening_balance`), `end`
  (`balance`), `payment`, `minimum`, `interest` and `fee` (`fees`). Used for the balance chart.
- `defaults`: the active plan's `strategy`, `extra_monthly`, `start_month` (the month of its
  `balances_as_of`) and structured `params`, so the form can show what is inherited.
- `affordability`: a conservative screen against `v_pay_period_forecast`, for the periods the
  forecast already displays (`full_plan_checked` is always `false`). Per period it reports the
  baseline obligations, the scenario's regular extra (spread across remaining calendar days),
  lump-sum cash (charged on its date), added income (overtime at `extra_hour_net` and raises,
  only in the pay period holding that pay date), released obligations (minimums of debts paid
  off earlier, stopped bills and debt minimums, and the active plan's own extra so it is not
  charged twice), projected cash and the gap to the low-balance floor (`flagged`,
  `cash_shortfall`). `status` is `unavailable`, `unfunded_what_if`, `at_risk` or
  `within_forecast`. Rainy-day money is not counted as available cash; `suggested_draw` is the
  smaller of the rainy-day balance and the peak gap, and nothing is moved.
