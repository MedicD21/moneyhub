# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

One user: Dustin, the owner. Hourly worker paid by paycheck (base, overtime and holiday pay; actual net amounts entered per check). Uses the app in two modes, about equally:

- **Quick phone checks:** "can I spend this?", safe-to-spend, logging a purchase right after it happens.
- **Pay-period planning:** around each paycheck, reviewing bills due, set-asides, envelope moves and the debt plan.

Often used at night.

## Product Purpose

A personal budgeting app that answers "how much can I safely spend right now, and what's coming before the next paycheck?" Success means the numbers on screen are always the same numbers the database computed, and the owner trusts them enough to act on them.

## Positioning

Not a bank-sync budgeting app. Data comes from bank screenshots read by a separate Claude chat project, which writes facts to Supabase through SQL procedures. The web app is a viewer over database-computed views with a small, deliberate set of writes. Forecasts are paycheck-based, not month-based.

## Operating Context

- Web app (Vite + React + TypeScript) on Vercel, mobile first, also used on desktop.
- Supabase Postgres is the single source of truth; all math lives in SQL views.
- A Claude chat project imports screenshots, reconciles transactions and maintains the debt plan. Its workflow is in `docs/CLAUDE_PROJECT_INSTRUCTIONS.md`; UI changes must not break it.
- Screens: Dashboard, Transactions (Activity), Bills, Paychecks (with Set-asides), Spending, Debts, Envelopes. A global + button adds a manual transaction.

## Capabilities and Constraints

- **The database does all the math.** The browser only displays view columns. No money arithmetic in the UI.
- **Writes are limited** to nine owner-checked database functions: manual transactions (add/edit/delete), cleared flag, envelope moves, envelope create/update, set-aside create/update.
- **Reconciliation is chat-only**, never in the web app.
- **Terminology is fixed:**
  - *Envelope*: virtual savings pot only (rainy-day fund, locked savings, user-named goal envelopes). No real money moves.
  - *Set-aside*: a per-paycheck reservation. Never called an envelope.
  - Goal envelopes are archived, not deleted. Set-asides are paused, not deleted.
  - A suggested draw comes only from the rainy-day fund and is never applied automatically.
- **Sign convention:** money in is positive, money out is negative. Debt balances are shown as positive amounts owed.
- Manual transactions count as `pending` until a screenshot import posts them. `Cleared` is the user's own note and changes no math.
- Sign-in is email + password for a single account; sign-ups are off.

## Brand Commitments

- Name: **Money Hub**.
- Voice: plain and terse. Short labels, numbers first, no encouragement, no commentary.

## Evidence on Hand

- Real financial data lives only in Supabase. Never invent balances, pay rates, bill amounts or dates in UI, mocks or copy; use real view output or clearly fake placeholder data in tests.
- Design and behavior record: `SPEC.md`, `docs/SPEC_REVIEW.md`, `web/README.md`.

## Product Principles

1. **Trust the number.** Every figure traces to a database view. Show it clearly; never recompute it.
2. **Answer first.** Safe-to-spend and what's due next lead; detail is one step away.
3. **Fast on the phone.** Checking or logging takes seconds, one-thumb, number pad for amounts.
4. **Words mean one thing.** Envelope, set-aside, pending, cleared, reconciled are never blurred.
5. **No surprises.** Nothing moves money or applies a suggestion without an explicit action.

## Accessibility & Inclusion

- Dark mode is first-class, not an afterthought; heavy night use.
- WCAG AA contrast in both themes. Touch targets at least 40px.
