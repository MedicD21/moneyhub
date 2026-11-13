# Money Hub: instructions for Claude Code

Personal budgeting app for one user (Dustin). Supabase (Postgres, project ref `elxgmzhgszuspsbrbrkq`) is the single source of truth. A Vite + React + TypeScript web app in `web/` is deployed on Vercel. A separate Claude chat project reads bank screenshots and writes data through SQL procedures. You are here for app, schema and test changes.

Read `SPEC.md` for the design and `docs/CLAUDE_PROJECT_INSTRUCTIONS.md` to see what the chat-side Claude does (so you don't break its workflow).

## Hard rules

1. **The database does all the math.** Totals, balances, forecasts, safe-to-spend, suggestions: all computed in SQL views. The web app only displays view columns. Do not add arithmetic on money in the browser. The one exception is integer-cents handling of the typed amount in `web/src/lib/money.ts`. If a screen needs a new number, add a view column in a migration.
2. **The browser never writes tables.** Tables and views are `SELECT`-only for the signed-in user (RLS). The only writes are nine owner-checked `SECURITY DEFINER` functions, called from exactly one file, `web/src/lib/writes.ts`:
   `add_manual_transaction`, `update_manual_transaction`, `delete_manual_transaction`, `set_transaction_cleared`, `move_envelope_money`, `create_envelope`, `update_envelope`, `create_set_aside`, `update_set_aside`.
   The browser sends only names, amounts and ids; the database validates and computes. Adding a tenth is a deliberate decision: ask first, then update the whitelist in `web/tests/readonly-guard.test.ts` and keep `eslint.config.js` consistent. The one read-only RPC, `simulate_debt_plan` (What if page), is called from `web/src/lib/reads.ts` only; it has its own whitelist in the same guard test and is not a write.
3. **Reconciliation is Claude-chat-only.** `reconcile_transactions` / `unreconcile_transactions` are never granted to `authenticated` and must never appear anywhere in `web/src` (a test enforces this). A trigger (`guard_transaction_reconciliation`) blocks web sessions from changing `reconciled`, `reconciled_at`, `entry_source`, from editing amount/date/account/status of reconciled rows, and from deleting reconciled or imported rows. Do not weaken it.
4. **Envelopes are virtual.** "Envelope" means only the virtual savings pots in `public.envelopes`: the rainy-day fund, locked savings, and user-named goal envelopes (kind `goal`, any number). A set-aside (`public.set_asides`) is a per-paycheck reservation, not an envelope; keep the two distinct in all copy. Active envelopes change what the forecast treats as spendable. No real money moves. Locked savings and goal envelopes are never used by the forecast. The rainy-day fund is manual moves only. A suggested draw is shown but never applied automatically, and only ever from the rainy-day fund. Goal envelopes are archived, not deleted (balance must be 0); set-asides are paused, not deleted.
5. **Never put credentials in code, commits, logs or chat.** The web bundle holds only the Supabase URL and anon key (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`).
6. **Don't invent data.** No made-up balances, rates, pay figures or dates. Pay rates, holidays and bill amounts come from the database or from Dustin.

## Commands

Run from the repo root or `web/`. Requires Node 22+.

- `npm run typecheck` (`tsc -b --noEmit`), `npm run lint`, `npm test` (vitest), `npm run build` (`tsc -b && vite build`)
- Before calling any web change done, run all four and read the output. Say what you ran.
- DB tests: `scripts/test-db-local.sh` runs the pgTAP suite in `supabase/tests/database` against a throwaway local Postgres (needs postgresql, pgtap, pg_cron, pg_prove). `scripts/local/supabase_shim.sql` stands in for Supabase's `auth` schema. The `...000700_cron.sql` migration needs pg_cron.

## Web conventions (`web/`)

- Stack: React 18, TypeScript strict, Vite, Tailwind 4, react-router 7, supabase-js 2.119, vitest, eslint with react-hooks 7.
- Reads go through `useView(key, build)` in `src/hooks/useView.ts`. Include `version` from `useEntry()` in the key of any query that should refresh after a write.
- Avoid `setState` inside effects (the react-hooks lint rule flags it). Reset forms by remounting with a `key`, as `TransactionSheet` does.
- Mobile first: money inputs use `inputMode="decimal"` so the phone shows the number pad. Touch targets at least 40px.
- Types for tables, views and RPCs live in `src/types/db.ts`. Update them together with any migration.
- Shared UI is in `src/components/ui.tsx`. Reuse it before adding new primitives.

## Database and migrations

- Migrations live in `supabase/migrations/` as `YYYYMMDDHHMMSS_name.sql`. Add new ones with a later timestamp. Never edit an applied migration.
- Production has `20261113060000_simulate_debt_plan.sql` (apply version `20261113055912`, 2026-11-13) on top of `20261113050000_set_aside_writes.sql` (applied 2026-11-12, after `20261113040000_goal_envelopes.sql`). `20261113070000_debt_scenario_affordability.sql` is applied too (apply version `20261113162900`, 2026-11-13); the What if page needs it. Production's history records versions by apply time (those are `20261113024614` and `20261113024709`), and `forecast_explain_columns` and `manual_entry_and_envelopes` were run by hand, so they are missing from it. Match by name, not version. Check `supabase migration list` before any `supabase db push`, so nothing gets re-applied. [unverified]
- Views must be `security_invoker`. `create or replace view` can reset that, so re-assert it (see `20261112165829_restore_security_invoker_on_recreated_views.sql`).
- `SECURITY DEFINER` functions use `set search_path = ''`, fully qualify names, and call `assert_app_owner()` first. Writes the Claude chat also uses call `app_owner_for_write()` instead: it runs `assert_app_owner()` for any request carrying a JWT (every web call) and uses `app_settings.owner_id` only for a direct database session with no JWT (the chat's Supabase connector, which runs as `postgres`).
- `pay_period_forecast` is the heart of the forecast. Change it only with a test and a before/after comparison of production values (cash 2049.33 and safe_to_spend 0.10 were the last verified figures on 2026-11-12, and will move as real data arrives).
- Prefer adding a pgTAP test under `supabase/tests/database` for any new function, trigger or view.

## Domain facts worth knowing

- Money in is positive, money out is negative.
- Manual transactions are stored with status `pending`, so balance views count them until a screenshot import posts them. `cleared` is the user's own note and changes no math.
- Paychecks: base 23.80/hr, overtime 35.70/hr, holiday pay is straight time, PERS 10%, benefits only on the first two checks by EFT month. Dustin enters actual net amounts through `pay_date_overrides`. Estimates must be replaced by actuals, never added on top.
- A raise is expected in January. When it lands, `income_sources.expected_net`, `app_settings.extra_hour_net` and `holiday_hour_net`, the 2027 three-check overrides and the debt plan all need updating. Ask Dustin for the figures.

## How to work

- Be direct. Lead with the problem or the risk. Tag uncertain claims as certain, likely or guessing.
- Read the surrounding code and the related migrations before changing anything. Change every file a change touches (types, tests, docs).
- When changing behavior, update `web/README.md` and `docs/CLAUDE_PROJECT_INSTRUCTIONS.md` if the chat-side workflow is affected.
- Known stale text: the root `README.md` and `package.json` still call the web app "read-only". Fix when next touching them.
- Dustin has approved Claude Code applying migrations to production. Rules for doing so:
  1. Test locally first with `scripts/test-db-local.sh` and get it passing.
  2. Before applying, record the key production values (`v_dashboard`, `v_pay_period_forecast` current row, row counts of tables the migration touches). After applying, re-query and report the before and after. Unexpected changes mean stop and tell Dustin.
  3. Migrations must be all-or-nothing (one transaction, or checks that raise before changing anything).
  4. Ask before anything destructive or irreversible: `drop table`, `drop column`, `truncate`, `delete` or `update` of existing rows without a tight `where`, or changing grants on `authenticated`. Never touch Dustin's financial data (transactions, debts, balances, pay overrides) unless that is the explicit task.
  5. Check `supabase migration list` first so applied migrations are not re-run, and keep the repo file and production identical.
  6. Report what was applied, by file name.
