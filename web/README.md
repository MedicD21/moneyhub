# Money Hub web (Phase 3)

A React app over the Money Hub Supabase views. It reads with
`.from(<view or table>).select(...)`, and every number on screen comes straight from a
view column. Its only writes are manual transactions and envelope moves, sent through
five narrow, owner-checked database functions (see "Write guarantees" below). The
database does all the math (see
`../supabase/migrations/20261112000300_views.sql` and `…000400_paycheck_and_dashboard.sql`).

Stack: React 18, TypeScript (strict), Vite, Tailwind CSS v4, Recharts, supabase-js v2, react-router.

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
user. The only writes are five `SECURITY DEFINER` functions that check the caller is the
app owner (`20261113000000_manual_entry_and_envelopes.sql`):

| Function | Used for |
| --- | --- |
| `add_manual_transaction` / `update_manual_transaction` / `delete_manual_transaction` | The + button and the Edit action on manual rows |
| `set_transaction_cleared` | The Cleared checkbox |
| `move_envelope_money` | Rainy-day fund and locked savings moves (virtual; no real money moves) |

- Manual rows are stored as `pending`, so balances count them until Claude's next screenshot import.
- **Reconciled is Claude-only.** `reconcile_transactions` / `unreconcile_transactions` are not
  granted to the web role, and a trigger blocks web sessions from changing `reconciled`,
  from editing the amount, date, account or status of a reconciled row, and from deleting
  reconciled or imported rows.
- `src/lib/writes.ts` is the only file that may call a database function.
  `tests/readonly-guard.test.ts` fails on any `.insert(`, `.update(`, `.upsert(` or `.delete(` in
  `src/`, on `.rpc(` anywhere except `writes.ts`, on any function not in the whitelist of five,
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
  pages/               Dashboard, Transactions, Bills, Paychecks, Spending, Debts
```

Sign convention: transaction `amount` < 0 is money out (shown neutral),
> 0 is money in (shown green with a `+`). Debt balances are amounts owed, positive.
