# Human setup: everything that needs your credentials or your hands

Everything in this repo is built and tested. The steps below are the parts no one else
can do: they need your Supabase, Claude and (optionally) Vercel accounts, or your eyes on
real bank screenshots. Do them in order. Expect about 45–60 minutes, plus data entry.

Legend: 🔑 needs a credential or account · ✋ manual check · ⏱ rough time

> Keep every secret out of git. The only keys that ever go in the web app are the
> **Project URL** and the **publishable/anon key**, never the `service_role`/secret key
> and never the database password.

## What was already verified (so you know what's left)

| Check                                                                                 | Result            | How                                                                                                                                                                            |
| ------------------------------------------------------------------------------------- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Migrations on Supabase's own Postgres 17                                              | **apply cleanly** | `supabase start` (local Docker stack)                                                                                                                                          |
| SQL suite: Phase 1 acceptance, security, Phase 2 screenshot logic, review regressions | **189/189 pass**  | `supabase test db`, on both an empty and a demo-seeded database                                                                                                                |
| Real Supabase API (PostgREST + GoTrue)                                                | **pass**          | Password login works. Reads return view data. Every write and writer-RPC attempt gets 403 / `42501`, anon gets 401, sign-ups and unknown emails are refused.      |
| Web app: typecheck, lint, 40 unit tests, production build                             | **pass**          | `npm run typecheck / lint / test / build`                                                                                                                                      |
| Web app in a browser against local Supabase                                           | **29/29 pass**    | Real password login (no emails sent), then every page: no console errors, no sideways scrolling, dashboard and paycheck numbers equal the views, console writes refused, sign-out works |

What's left is only what needs your hosted project and real data: steps 1–11 below.

---

## 0. Before you start 🔑

| You need                                                                              | Why                                                  |
| ------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| Supabase account (ideally the same email you'll log in to Money Hub with; see step 5) | Database, Auth, cron                                 |
| Claude plan with Projects + connectors (Pro/Max/Team)                                 | The "Money" Project                                  |
| Node.js 20+ and npm                                                                   | Supabase CLI via `npx`, web app                      |
| Git access to this repo (`MedicD21/moneyhub`)                                         | Pull the code                                        |
| _(optional)_ Vercel account                                                           | Hosting the web app (otherwise run it locally)       |
| _(optional)_ Docker Desktop                                                           | Running the test suite locally with `supabase start` |

---

## 1. Create the Supabase project 🔑 ⏱ 5 min

1. https://supabase.com/dashboard → **New project**. Name: `money-hub`. Make it a _new, dedicated_ project, separate from TGK (SPEC S1).
2. Pick the region closest to you. Generate a strong **database password** and store it in your password manager (the CLI asks for it once).
3. Note the **project ref** (the 20-letter id in the dashboard URL / _Project Settings → General_). You'll use it 3 times below.
4. Plan note **[Likely]**: free-tier projects are paused after a period of inactivity, and a paused project runs no cron and serves no app. If you'll go more than about a week without using it, use a paid plan or open the app regularly. Paid plans also include daily backups; see step 12.

## 2. Apply the database migrations 🔑 ⏱ 5 min

From the repo root:

```bash
npx supabase login                       # opens a browser; uses your Supabase account
npx supabase link --project-ref <REF>    # asks for the database password from step 1
npx supabase db push --dry-run           # shows the 7 migrations it will apply
npx supabase db push                     # applies them
```

- **Do not** pass `--include-seed`. `supabase/seed.sql` is demo data for local development only.
- No CLI? Paste each file in `supabase/migrations/` into _SQL Editor_ **in filename order** and run it.

✋ Verify in _SQL Editor_:

```sql
select jobname, schedule, command from cron.job;          -- ensure-bill-occurrences | 0 5 * * *
select count(*) from pg_policies where schemaname = 'public';  -- 14
```

If the cron row is missing, enable **Integrations → Cron** in the dashboard and re-run
`supabase/migrations/20261112000700_cron.sql` in the SQL editor.

## 3. Run the test suite on the real project (recommended) ⏱ 2 min

Do this **now, before entering any real data**. A few tests count rows and would fail
once your data exists. Every test runs inside a transaction that is rolled back, so nothing persists.

```bash
npx supabase test db --linked
```

Expected: `All tests successful … Tests=189 … Result: PASS`. This confirms the suite on
Supabase's Postgres version (it was built and run on PG16 here).

## 4. Auth settings 🔑 ⏱ 5 min

In the Supabase dashboard:

1. **Authentication → Sign In / Providers**
   - Turn **off** "Allow new users to sign up" (SPEC §6.1).
   - Make sure the **Email** provider stays **enabled**. Magic links use it, and turning it off blocks your own login ("Email logins are disabled"). Only the sign-up toggle goes off.
2. **Authentication → URL Configuration**: not needed for password login. Set the Site URL to your Vercel URL anyway.

## 5. Create your user and bootstrap the owner 🔑 ⏱ 3 min

1. **Authentication → Users → Add user → Create new user.** Enter your email and a password, and tick **Auto Confirm User**.
2. In _SQL Editor_ run (your email and IANA time zone):
   ```sql
   select public.bootstrap_owner('dschaaf12@me.com', 'America/New_York');
   ```
   This stores your user id as the owner of all data and seeds the 18 categories.

✋ `select * from app_settings;` shows one row with your user id.

**Password:** the web app signs in with email + password, and no emails are ever sent. If you
didn't set a password when creating the user, or want to change it, run
`scripts/set-password.sh you@example.com` from the repo root. It prompts and never echoes.

## 6. Connect Claude to Supabase 🔑 ⏱ 10 min

1. In Claude (claude.ai → **Settings → Connectors**), add the Supabase connector as a **custom connector** with this URL:
   ```
   https://mcp.supabase.com/mcp?project_ref=<REF>&features=database,docs
   ```

   - `project_ref` scopes it to money-hub only, with no access to other projects or account tools (confirmed in Supabase's MCP docs).
   - `features=database,docs` hides edge functions, storage, branching and account management.
   - Do **not** add `read_only=true`. Claude must be able to write transactions.
2. Sign in to Supabase when prompted (OAuth) and approve access.
3. In the connector's tool permissions, set **`execute_sql` → Needs approval** and **`apply_migration` → Never/blocked** if offered, otherwise Needs approval (SPEC S2). The Project instructions forbid schema changes, and the permission setting is the hard stop. **[Likely]** the exact labels differ slightly in the UI.

**Know the risk:** connector SQL runs as `postgres`, which bypasses RLS and could drop
tables. The approval prompt is the only guard. Read each SQL statement before approving,
especially anything that isn't a `select`, `preview_…`, `commit_…` or `mark_bill_paid`.

## 7. Create the Claude Project "Money" ⏱ 5 min

1. **Settings → Capabilities**: turn on **Code execution** (SPEC S4) so forecasts are computed, not estimated.
2. **Projects → New project** → name it `Money`.
3. **Instructions**: paste the fenced block from [`docs/CLAUDE_PROJECT_INSTRUCTIONS.md`](CLAUDE_PROJECT_INSTRUCTIONS.md).
4. **Project knowledge**: upload [`docs/CLAUDE_PROJECT_KNOWLEDGE.md`](CLAUDE_PROJECT_KNOWLEDGE.md).
5. In a chat inside the Project, make sure the Supabase connector is enabled, then ask: _"money update"_. ✋ Claude should query `v_dashboard` (all zeros or empty is correct at this point).

## 8. Enter your setup data by chat (Phase 2) ✋ ⏱ 20–40 min

Gather this first. Claude restates each change and waits for your OK.

| What           | Details to have ready                                                                                                                                                                                                             |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Accounts**   | name, bank, kind (checking/savings/credit_card/loan/cash), last 4, and whether the balance your bank app shows _includes pending_ transactions (most don't)                                                                       |
| **Income**     | per source: frequency, the date of a real past payday, net amount, semimonthly days if applicable, and what happens when payday is on a weekend                                                                                   |
| **Bills**      | name, amount (and whether it varies), frequency, due day (or a real due date for weekly/quarterly/annual), autopay?, which account pays it, category, and the text that appears on your statement when it's paid (e.g. `XFINITY`) |
| **Debts**      | name, type, linked account (for cards you screenshot), APR, minimum, due day, credit limit, promo APR + end date, current balance + as-of date                                                                                    |
| **Set-asides** | name and amount per paycheck                                                                                                                                                                                                      |

Don't create bills for debt minimums. `paycheck_plan()` already subtracts them.

## 9. Phase 2 acceptance with real screenshots ✋ ⏱ 15 min

1. Send a screenshot of one account (with the balance visible) → review Claude's table → "ok".
2. Send a **second screenshot that overlaps the first** (scrolled a few rows) → the table must show the overlapping rows as `skip`.
3. Wait until a pending item posts, then screenshot again → that row must show `update`, not `insert`.
4. After each commit, Claude reports the balance check. ✋ It must be `0`. If it isn't, look at `likely_cause`: the usual causes are a missed row, a misread digit, or `balance_includes_pending` set wrong for that account.
5. ✋ In _SQL Editor_, confirm no duplicates:
   ```sql
   select account_id, txn_date, amount, description_raw, count(*)
   from transactions group by 1,2,3,4 having count(*) > 1;   -- only genuine same-day repeats
   ```

## 10. Run / deploy the web app (Phase 3) 🔑 ⏱ 10 min

Keys come from _Project Settings → API Keys_ (or _Data API_): the **Project URL** and the
**publishable key** (`sb_publishable_…`) or the legacy **anon** key. Never the secret/service_role key.

**Local:**

```bash
cd web
cp .env.example .env.local     # set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm ci
npm run dev                    # http://localhost:5173
```

**Vercel** (SPEC S5 left this open; the app supports both):

1. vercel.com → **Add New → Project** → import `MedicD21/moneyhub`.
2. **Root Directory:** `web` · Framework preset: **Vite** · Build: `npm run build` · Output: `dist`.
3. Environment variables: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`.
4. Deploy. Vite bakes the env vars in at build time, so redeploy after changing them.
5. Optional: _Vercel → Settings → Deployment Protection_ to require Vercel login. The app has its own login, so this is extra defense.

## 11. Phase 3 acceptance ✋ ⏱ 10 min

**Numbers match the SQL editor.** For each, compare the screen to the query:

| Screen             | Query                                                                                                                               |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| Dashboard cards    | `select * from v_dashboard;`                                                                                                        |
| Accounts list      | `select name, estimated_balance_display, days_since_screenshot from v_account_balances;`                                            |
| Paychecks          | `select period_offset, period_start, safe_to_spend from v_pay_periods order by 1;`                                                  |
| Bills (this month) | `select bill_name, due_date, status, remaining_amount from v_bill_status where due_month = date_trunc('month', app_today())::date;` |
| Spending           | `select * from v_cash_flow order by month desc;`                                                                                    |
| Debts              | `select name, balance, effective_apr, utilization_pct from v_debts;`                                                                |

Note: the SQL editor runs as `postgres` and sees every row. With one owner that's the same data the app shows.

**The app cannot write.** While logged in, open the browser console on the app and run
(fill in your URL and publishable/anon key):

```js
const URL = "https://<REF>.supabase.co",
  KEY = "<publishable-or-anon-key>";
const tok = JSON.parse(
  localStorage.getItem(
    Object.keys(localStorage).find((k) => k.endsWith("-auth-token")),
  ),
).access_token;
const h = {
  apikey: KEY,
  Authorization: `Bearer ${tok}`,
  "Content-Type": "application/json",
};
for (const [m, path, body] of [
  ["POST", "/rest/v1/accounts", { name: "hack", kind: "cash" }],
  ["PATCH", "/rest/v1/accounts?name=neq.__none__", { name: "hacked" }],
  ["DELETE", "/rest/v1/transactions?amount=lt.0", null],
  ["POST", "/rest/v1/rpc/ensure_bill_occurrences", {}],
]) {
  const r = await fetch(URL + path, {
    method: m,
    headers: h,
    body: body ? JSON.stringify(body) : undefined,
  });
  console.log(m, path, r.status, await r.text());
}
```

✋ Expected: every line is **401 or 403** with `"code":"42501"` (permission denied). Nothing changes in the data.

## 12. Backups & housekeeping 🔑

- Paid plans include daily backups (_Database → Backups_). Point-in-time recovery is an add-on. **[Likely]**
- On any plan you can export: `npx supabase db dump --data-only -f backup-$(date +%F).sql`. Store it encrypted, since it's your financial history.
- If a key or the DB password leaks: rotate it in _Project Settings_, then update `.env.local` / Vercel.

---

## What I did NOT do (needs you)

| Item                                                           | Why it needs you                                                              |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Create the Supabase project, push migrations, create your user | Your Supabase account + DB password                                           |
| Configure Auth settings / SMTP                                 | Dashboard access; SMTP provider credentials                                   |
| Add the Claude connector and Project                           | Your Claude account; OAuth consent                                            |
| Deploy to Vercel                                               | Your Vercel account                                                           |
| Run Phase 2 acceptance with real screenshots                   | Needs your real bank app                                                      |
| Run the suite on hosted Supabase (`supabase test db --linked`) | Needs the linked project. It was run on local PG16 here (189/189 passing)     |
| Open a pull request                                            | You didn't ask for one; the work is on branch `claude/friendly-edison-4majyc` |
