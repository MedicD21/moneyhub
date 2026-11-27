# Money Hub web (Phase 3)

A React app over the Money Hub Supabase views. It reads with
`.from(<view or table>).select(...)`, and every number on screen comes straight from a
view column. Its only writes are manual transactions, classifying transactions (review inbox),
merchant rules, envelope moves and envelope / set-aside settings, sent through thirteen narrow, owner-checked database functions (see "Write guarantees" below). The
database does all the math (see
`../supabase/migrations/20261112000300_views.sql` and `…000400_paycheck_and_dashboard.sql`).

Stack: React 18, TypeScript (strict), Vite, Tailwind CSS v4, Recharts, supabase-js v2, react-router.

The **Planner** page (`/planner`, desktop side nav, and the "Plan overtime" button on Paychecks) lists every upcoming paycheck
with two inputs: extra overtime hours and spending money (food, gas). Each card names the work period
the paycheck pays for (14 days ending 5 days before the scheduled payday, so Dec 9 pays Nov 21 - Dec 4),
so it is clear which overtime shifts belong on which check. The read-only
`shortfall_plan_forecast` RPC layers them onto the daily forecast (overtime at `app_settings.extra_hour_net`
per hour on that paycheck, spending held back from the start of its pay period) and returns the lowest
balance, the room left to spend, and suggested extra hours per paycheck. An unsaved draft is recalculated as
you type; "Save plan" stores it with `save_shortfall_plan`. Overtime is ignored on a paycheck that is paid or
whose real net is entered (the actual already includes it). The plan never changes the Dashboard or the real
forecast, and a dip in a pay period that has already started is reported as one overtime cannot fix.

The **What if** page (`/what-if`) previews debt-payoff scenarios through the read-only
`simulate_debt_plan` RPC (strategy, extra monthly, lump sums, raise, overtime, early payoff,
stopped payments). The scenario lives in the page URL; nothing is saved and the active plan is
never changed. The RPC is called only from `src/lib/reads.ts`, and the write-surface guard test
whitelists it (and `shortfall_plan_forecast`) separately from the thirteen writes. Inputs, Affirm principal estimates, the
affordability screen and the historical regression are in
[debt simulation](../docs/debt-simulation.md).

## Local development

Requires Node 22+.

```bash
cd web
cp .env.example .env.local   # then fill in the two values
npm install
npm run dev                  # http://localhost:5173
```

| Script              | What it does                                                     |
| ------------------- | ---------------------------------------------------------------- |
| `npm run dev`       | Vite dev server                                                  |
| `npm run build`     | `tsc -b && vite build` into `dist/`                              |
| `npm run typecheck` | TypeScript project build, no output                              |
| `npm run lint`      | ESLint (typescript-eslint type-checked rules, react-hooks)       |
| `npm run test`      | Vitest: `format.ts` and `money.ts` unit tests and the write-surface guard           |

### Environment variables

| Name                     | Value                                                                       |
| ------------------------ | --------------------------------------------------------------------------- |
| `VITE_SUPABASE_URL`      | `https://<project-ref>.supabase.co` (Project Settings → API / Connect)       |
| `VITE_SUPABASE_ANON_KEY` | The **anon** (legacy) or **publishable** key. Never the service-role/secret key. |

Both are inlined into the browser bundle at build time. That is safe: the
anon role has no grants, and the `authenticated` role can only `SELECT` the
owner's rows (RLS, `20261112000600_security.sql`). If either variable is
missing or malformed the app shows a setup screen instead of crashing.

## Write guarantees

The browser can never write a table. Tables and views are `SELECT`-only for the signed-in
user. The only writes are thirteen `SECURITY DEFINER` functions that check the caller is the
app owner. The browser sends names, amounts and ids; the database validates them and computes
every balance:

| Function | Used for |
| --- | --- |
| `add_manual_transaction` / `update_manual_transaction` / `delete_manual_transaction` | The + button and the Edit action on manual rows |
| `set_transaction_cleared` | The Cleared checkbox |
| `move_envelope_money` | Moves into or out of any envelope (virtual; no real money moves). A move in is refused if envelopes plus set-aside balances would exceed real cash (`20261113030000`) |
| `create_envelope` / `update_envelope` | Envelopes page: new goal envelope (name only, starts at $0), rename, archive (balance must be $0), restore. The rainy-day fund and locked savings are fixed (`20261113040000`) |
| `create_set_aside` / `update_set_aside` | Paychecks page, Set-asides section: create, edit, pause / resume. The balance stays derived in `v_set_asides` (`20261113050000`) |
| `delete_set_aside` | Set-asides section: Delete on a paused set-aside (tap twice). Refused while it is active or while bank-reconciled transactions are tagged to it (the reconciliation guard is not weakened); unreconciled tagged rows keep everything but the link (`20261127190000`) |
| `save_shortfall_plan` | Planner page: Save plan. Stores only hours and spending money per paycheck in `shortfall_plans` (replaces the saved plan; zero rows dropped); the plan never feeds the real forecast (`20261127210000`) |
| `review_transaction` | Review page (`/review`) and "Review" / "Edit details" on imported or reconciled rows: category, note, bill or debt link, and resolving the review question. Works on any row; never changes amount, date, merchant, status, cleared or reconciliation (`20261115000000`) |
| `create_merchant_rule` | "Always do this for [merchant]" in the review form: saves a case-insensitive pattern + category. Applied to future imports by `commit_screenshot_import`, and to other open uncategorized reviews that match (`20261115000000`) |

- Manual rows are stored as `pending`, so balances count them until Claude's next screenshot import.
- **Rows from the bank are classify-only.** Imported or reconciled rows open a details form with amount,
  date and merchant read-only ("From your bank. Ask Claude to fix a wrong amount or date."). Open manual
  rows keep the full edit.
- **Review inbox.** `/review` lists `v_review_queue` newest first, one card at a time (Save and next / Skip).
  It is in the desktop rail with a count from `v_dashboard.review_queue_count`; on phones it is reached from
  the Dashboard "Needs attention > To review" row.
- **Reconciled is Claude-only.** `reconcile_transactions` / `unreconcile_transactions` are not
  granted to the web role, and a trigger blocks web sessions from changing `reconciled`,
  from editing the amount, date, account or status of a reconciled row, and from deleting
  reconciled or imported rows.
- `src/lib/writes.ts` is the only file that may call a database function.
  `tests/readonly-guard.test.ts` fails on any `.insert(`, `.update(`, `.upsert(` or `.delete(` in
  `src/`, on `.rpc(` anywhere except `writes.ts`, on any function not in the whitelist of thirteen,
  and on any mention of the reconcile functions. ESLint has matching `no-restricted-syntax` rules.
- `src/types/db.ts` gives the typed client `Insert`/`Update` types with no keys, so a direct
  table write would also fail to compile.

## Deploying to Vercel

1. Import the repo in Vercel and set **Root Directory** to `web`.
2. Framework preset: **Vite** (build `npm run build`, output `dist`; the defaults are correct).
3. Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` under Project Settings →
   Environment Variables (Production and Preview). Redeploy after changing them,
   because Vite bakes them in at build time.
4. `vercel.json` rewrites every path to `/index.html`, so deep links such as
   `/bills?month=2026-11-01` work on refresh.

## Supabase Auth settings

Sign-in is **email + password** (`signInWithPassword`). No emails are sent, so no
SMTP setup or redirect URLs are needed. In the Supabase dashboard:

- **Authentication → Sign In / Providers**: keep the **Email** provider enabled (password
  login uses it); turn **Allow new users to sign up** off.
- The owner account must already exist and be confirmed. Set or change its password
  with `scripts/set-password.sh` from the repo root (prompts, never echoes).
- A wrong password and an unknown email both show "Email or password is incorrect."

## Layout

```
src/
  lib/supabase.ts      client (null + configError when env is missing)
  lib/format.ts        currency/date formatting (no timezone shift on 'YYYY-MM-DD')
  lib/authErrors.ts    sign-in error messages
  hooks/useView.ts     generic typed query hook -> { data, error, loading, count, reload }
  hooks/useAuth.tsx    session context + sign-out
  hooks/useParams.ts   URL search params as filter state
  types/db.ts          row types for every view, matching the SQL column names
  components/          layout/nav, cards, badges, query states, charts
  components/BillsCalendarFull.tsx  full-screen bills calendar (Bills page, Calendar button): bills from v_bill_status,
                       projected end-of-day spendable balance per day from v_daily_balance_forecast
  pages/               Dashboard, Transactions, Review, Bills, Paychecks, Spending, Debts
```

Sign convention: transaction `amount` < 0 is money out (shown neutral),
> 0 is money in (shown green with a `+`). Debt balances are amounts owed, positive.
