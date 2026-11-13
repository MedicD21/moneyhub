# Money Hub

Personal finances with **Supabase as the single source of truth**. A **Claude Project**
reads bank-app screenshots and writes facts. A **web app with narrow writes** shows the
numbers and lets you add manual entries and move virtual envelope money. Every total,
balance and safe-to-spend figure is computed by SQL views, so Claude and the web app
always report the same numbers.

```
Claude Project "Money" ──(Supabase connector: SQL)──┐
                                                    ▼
                         Supabase: tables (facts) → views/functions (math) ← pg_cron
                                                    ▲
Web app (React, RLS) ──(select + 5 owner-checked functions)─┘
```

## Write model

The browser never writes a table. Tables and views are `SELECT`-only for the signed-in
user (RLS). The only writes are five `SECURITY DEFINER` functions that check the caller is
the app owner, called from one file (`web/src/lib/writes.ts`): `add_manual_transaction`,
`update_manual_transaction`, `delete_manual_transaction`, `set_transaction_cleared` and
`move_envelope_money`. Reconciliation stays with Claude: `reconcile_transactions` and
`unreconcile_transactions` are not granted to the web role, and a trigger blocks web
sessions from changing reconciled rows. Details: [`web/README.md`](web/README.md#write-guarantees).

## Start here

| If you want to… | Read |
|---|---|
| **Set it up** (things that need your accounts/credentials) | [`docs/HUMAN_SETUP.md`](docs/HUMAN_SETUP.md) |
| Know what changed from the spec, and why | [`docs/SPEC_REVIEW.md`](docs/SPEC_REVIEW.md) |
| Paste the Claude Project instructions | [`docs/CLAUDE_PROJECT_INSTRUCTIONS.md`](docs/CLAUDE_PROJECT_INSTRUCTIONS.md) + [`docs/CLAUDE_PROJECT_KNOWLEDGE.md`](docs/CLAUDE_PROJECT_KNOWLEDGE.md) |
| Read the original spec | [`SPEC.md`](SPEC.md) |
| Work on the web app | [`web/README.md`](web/README.md) |

## Repository layout

```
supabase/
  migrations/      migrations: schema, schedule functions, views, paycheck/dashboard,
                   Claude procedures, security (RLS + grants), pg_cron, forecast,
                   manual entry and envelopes
  tests/database/  pgTAP suite (278 assertions): Phase 1 and 2 acceptance checks,
                   plus manual entry, the reconciliation guard and envelopes
  tests/local/     Supabase shim for running the suite on plain Postgres
  seed.sql         LOCAL demo data only (never push it to your real project)
  config.toml      Supabase CLI config (sign-ups disabled)
scripts/
  test-db-local.sh run the SQL suite on a throwaway local Postgres (no Docker)
web/               React + TypeScript + Vite + Tailwind + Recharts; reads views, writes only
                   through five owner-checked functions
docs/              setup, spec review, Claude Project instructions
```

## Database tests

```bash
# With Docker + Supabase CLI
npx supabase start && npx supabase test db

# Without Docker (needs postgresql-16, postgresql-16-pgtap, postgresql-16-cron, pg_prove)
scripts/test-db-local.sh

# Against your hosted project, before entering real data (everything rolls back)
npx supabase test db --linked
```

## Web app

```bash
cd web
cp .env.example .env.local   # VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY
npm ci
npm run dev
```

For local development against demo data: `npx supabase start` (applies migrations +
`seed.sql`), point `.env.local` at `http://127.0.0.1:54321` with the local publishable key
from `npx supabase status`, and sign in as `demo@moneyhub.local` / `moneyhub-demo-password`.

## Ground rules (enforced, not just documented)

- Sign convention: transaction `amount` **negative = money out, positive = money in**.
- Card/loan balances are stored **as displayed** (owed = positive). Views handle the sign.
- The web app role (`authenticated`) can only `SELECT` its own rows. Writes, TRUNCATE and
  writer functions are refused at the database (tested).
- Every Claude write belongs to an `import_batch`. Deleting the batch undoes it (and un-pays
  any bill it marked paid).
