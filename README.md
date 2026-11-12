# Money Hub

Personal finances with **Supabase as the single source of truth**. A **Claude Project**
reads bank-app screenshots and writes facts. A **read-only web app** shows the numbers.
Every total, balance and safe-to-spend figure is computed by SQL views, so Claude and the
web app always report the same numbers.

```
Claude Project "Money" ──(Supabase connector: SQL)──┐
                                                    ▼
                         Supabase: tables (facts) → views/functions (math) ← pg_cron
                                                    ▲
Web app (React, read-only, RLS) ──(select only)─────┘
```

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
  migrations/      7 migrations: schema, schedule functions, views, paycheck/dashboard,
                   Claude procedures, security (RLS + grants), pg_cron
  tests/database/  pgTAP suite (169 assertions): every Phase 1 acceptance check,
                   plus the Phase 2 screenshot acceptance checks
  tests/local/     Supabase shim for running the suite on plain Postgres
  seed.sql         LOCAL demo data only (never push it to your real project)
  config.toml      Supabase CLI config (sign-ups disabled)
scripts/
  test-db-local.sh run the SQL suite on a throwaway local Postgres (no Docker)
web/               React + TypeScript + Vite + Tailwind + Recharts, read-only
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
from `npx supabase status`, and sign in as `demo@moneyhub.local`. The magic link arrives
in Mailpit at http://127.0.0.1:54324.

## Ground rules (enforced, not just documented)

- Sign convention: transaction `amount` **negative = money out, positive = money in**.
- Card/loan balances are stored **as displayed** (owed = positive). Views handle the sign.
- The web app role (`authenticated`) can only `SELECT` its own rows. Writes, TRUNCATE and
  writer functions are refused at the database (tested).
- Every Claude write belongs to an `import_batch`. Deleting the batch undoes it (and un-pays
  any bill it marked paid).
