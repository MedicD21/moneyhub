# Shortfall Planner: draft design notes

Status: APPROVED by Dustin on 2026-11-27 (Plan A, "make it happen"). Built in PR feat/shortfall-planner; migration `20261127210000_shortfall_planner.sql` applied to production as `shortfall_planner`.

## What Dustin asked for (his words, condensed)
- A new tab beside Paychecks, similar but much less detailed: a roadmap through each paycheck.
- Per paycheck, an input for extra overtime (OT) hours. Dustin picks which paycheck gets the hours.
- The page estimates the extra net pay those hours add to that paycheck and updates the forecast.
- It shows how much OT is needed to get out of the shortfall, and gives suggestions.
- He can also add an amount of spending money (food, gas and similar) that comes out of safe-to-spend.

## Forecast facts (production, 2026-11-27, after the Home Chef and Affirm imports)
- Cash 1,505.07.
- Lowest projected balances: Dec 8 -255.60, Mar 14 -150.65, Apr 13 -904.36, May -233.07.
- The "34 extra hours" hint is ceil(904.36 / 26.80). `app_settings.extra_hour_net` is 26.80 and `holiday_hour_net` is 17.86.
- Levelized safe-to-spend is 0.00 after period 1. Period 1 is -904.36 with binding date 2027-04-13.
- The forecast covers scheduled items only: no groceries, gas or dining.

## Findings from the code
- `pay_period_forecast` builds income from `paycheck_plan(pay_date)` items. `daily_balance_forecast` is cumulative, so extra income deposited on a day lifts every later balance.
- Precedent for a read-only scenario page: `WhatIf.tsx` with `ScenarioControls.tsx` and `ScenarioResults.tsx`. It calls `simulate_debt_plan` through `web/src/lib/reads.ts` only.
- A new read RPC must be added to `ALLOWED_READ_RPCS` in `web/tests/readonly-guard.test.ts`. That is not a write.
- Saving a plan between visits would be a 13th write function. Per CLAUDE.md, ask Dustin first, then update the write whitelist in the guard test and keep `eslint.config.js` consistent.
- The database does all the math. The browser may only handle the typed amount as integer cents (`web/src/lib/money.ts`).

## Approaches considered
- **A. One saved plan with a live preview (chosen by Dustin).** New table `shortfall_plans`, read-only `shortfall_plan_forecast`, one write `save_shortfall_plan` (the 13th write, approved). The plan never feeds the real forecast.
- **B. Several named plans.** Rejected: three write functions, more than asked for.
- **C. Saved hours flow into the real forecast and Dashboard.** Rejected: estimates would sit in real safe-to-spend and `pay_period_forecast` would change.

## Decisions (Dustin's choices and builder calls)
- Dustin: saved plan so he can come back and review it; he picks which paycheck gets the hours; spending money is entered per paycheck.
- Builder call: hours are entered on the paycheck that receives the pay, so there is no pay-lag assumption.
- Builder call: overtime is ignored once a paycheck is paid or has a real net in `pay_date_overrides` (the actual already includes it).
- Builder call: spending is held back from the first day of that pay period (today for the current one), the cautious reading.
- Builder call: suggestions are whole extra hours, working forward paycheck by paycheck, counting earlier suggestions; a dip in a period that already started is reported as unfixable.
- Builder call: desktop side-nav entry plus a "Plan overtime" button on Paychecks (the phone dock has room for six tabs).

## Risks and caveats
- Dec 8 cannot be fixed by OT. The next paycheck is Dec 9, so roughly 10 hours (about $255.60) of the gap would have to be covered another way.
- Estimates must be replaced by actual net amounts (`pay_date_overrides`), never added on top.
- $26.80 per hour is a flat net estimate. A January raise will change it.
- Whether OT worked in a period pays on that period's check or the next is unconfirmed [Guessing].
- The forecast excludes groceries, gas and dining. That is why the spending input matters.

## Open items
- Dustin to confirm how overtime worked in a period is actually paid (that period's check or the next); the planner avoids the question by letting him choose the paycheck.
- A January raise changes `app_settings.extra_hour_net`; the planner uses whatever it holds.
