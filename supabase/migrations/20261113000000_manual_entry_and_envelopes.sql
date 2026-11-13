-- Manual transaction entry, Claude-only reconciliation, and virtual envelopes.
--
-- 1. transactions gain: cleared (you saw it clear at the bank), reconciled (Claude matched it to a bank
--    screenshot; only Claude can set it), reconciled_at, entry_source ('import' | 'manual').
--    Manual rows are written with status 'pending' so the balance views keep counting them as outside the
--    last snapshot until Claude's next screenshot import posts and reconciles them.
-- 2. The web app is still SELECT-only on tables. Writes go through five narrow SECURITY DEFINER functions
--    that check the caller is the owner. A trigger blocks any web session from touching reconciliation.
-- 3. Two virtual envelopes (rainy_day, locked_savings). No real money moves: each envelope is a ledger of
--    manual moves, and its balance is subtracted from the cash the forecast can spend. The forecast never
--    draws on either automatically; v_rainy_day_suggestion proposes a draw for you to confirm.

-- ---------------------------------------------------------------------------
-- 1. transactions columns
-- ---------------------------------------------------------------------------
alter table public.transactions
  add column cleared       boolean     not null default false,
  add column reconciled    boolean     not null default false,
  add column reconciled_at timestamptz,
  add column entry_source  text        not null default 'import' check (entry_source in ('import', 'manual'));

comment on column public.transactions.cleared is
  'User attests the transaction has cleared at the bank. Informational: does not affect balance math.';
comment on column public.transactions.reconciled is
  'Claude matched this row to a bank screenshot. Only Claude (privileged role) can change it.';
comment on column public.transactions.entry_source is
  'import = read from a screenshot or chat by Claude; manual = typed into the web app.';

-- Existing rows: posted rows are cleared; rows Claude read from bank screenshots are already reconciled.
update public.transactions t set cleared = true where t.status = 'posted';
update public.transactions t
   set reconciled = true, reconciled_at = t.created_at
  from public.import_batches b
 where b.id = t.import_batch_id and b.source = 'screenshot' and t.status = 'posted';

create index transactions_unreconciled_idx on public.transactions (txn_date desc) where not reconciled;

-- ---------------------------------------------------------------------------
-- 2a. Session helpers and the reconciliation guard
-- ---------------------------------------------------------------------------
-- True for a request that came through PostgREST as a signed-in user (the web app). False for the SQL
-- editor, migrations and Claude's privileged connector.
create or replace function public.is_web_session()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(
           nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
           nullif(current_setting('request.jwt.claim.role', true), ''),
           '') = 'authenticated';
$$;

create or replace function public.assert_app_owner()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_owner uuid;
begin
  select s.owner_id into v_owner from public.app_settings s where s.id;
  if auth.uid() is null or auth.uid() is distinct from v_owner then
    raise exception 'Not signed in as the Money Hub owner' using errcode = '42501';
  end if;
  return v_owner;
end;
$$;

create or replace function public.guard_transaction_reconciliation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not public.is_web_session() then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'INSERT' then
    if new.reconciled or new.reconciled_at is not null or new.entry_source <> 'manual' then
      raise exception 'The web app can only add unreconciled manual entries' using errcode = '42501';
    end if;
    return new;
  elsif tg_op = 'UPDATE' then
    if new.reconciled is distinct from old.reconciled or new.reconciled_at is distinct from old.reconciled_at then
      raise exception 'Only Claude can change reconciliation' using errcode = '42501';
    end if;
    if new.entry_source is distinct from old.entry_source then
      raise exception 'entry_source cannot be changed' using errcode = '42501';
    end if;
    if old.reconciled
       and (new.amount     is distinct from old.amount
         or new.txn_date   is distinct from old.txn_date
         or new.account_id is distinct from old.account_id
         or new.status     is distinct from old.status
         or not new.cleared) then
      raise exception 'A reconciled transaction can no longer be changed' using errcode = '42501';
    end if;
    return new;
  else
    if old.reconciled then
      raise exception 'A reconciled transaction cannot be deleted' using errcode = '42501';
    end if;
    if old.entry_source <> 'manual' then
      raise exception 'Only manual entries can be deleted from the web app' using errcode = '42501';
    end if;
    return old;
  end if;
end;
$$;

create trigger guard_transaction_reconciliation
  before insert or update or delete on public.transactions
  for each row execute function public.guard_transaction_reconciliation();

-- ---------------------------------------------------------------------------
-- 2b. Manual entry functions (called by the web app)
-- ---------------------------------------------------------------------------
create or replace function public.add_manual_transaction(
  p_amount             numeric,
  p_txn_date           date,
  p_merchant           text,
  p_account_id         uuid    default null,
  p_category_id        uuid    default null,
  p_note               text    default null,
  p_cleared            boolean default false,
  p_bill_occurrence_id uuid    default null,
  p_debt_id            uuid    default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner   uuid := public.assert_app_owner();
  v_account uuid := p_account_id;
  v_desc    text := nullif(btrim(coalesce(p_merchant, '')), '');
  v_note    text := nullif(btrim(coalesce(p_note, '')), '');
  v_today   date := public.app_today();
  v_kind    text;
  v_fp      text;
  v_occ     int;
  v_id      uuid;
begin
  if p_amount is null or p_amount = 0 then raise exception 'Enter an amount'; end if;
  if round(p_amount, 2) <> p_amount then raise exception 'Amounts have at most two decimal places'; end if;
  if abs(p_amount) > 1000000 then raise exception 'That amount is too large'; end if;
  if p_txn_date is null then raise exception 'Choose a date'; end if;
  if p_txn_date > v_today then raise exception 'The date cannot be in the future'; end if;
  if p_txn_date < v_today - 400 then raise exception 'The date is more than 400 days ago'; end if;
  if v_desc is null then raise exception 'Enter who you paid or who paid you'; end if;
  if length(v_desc) > 120 then raise exception 'The name is too long (120 characters max)'; end if;
  if v_note is not null and length(v_note) > 500 then raise exception 'The note is too long (500 characters max)'; end if;

  if v_account is null then
    -- default: the only active checking account
    if (select count(*) from public.accounts a where a.owner_id = v_owner and a.is_active and a.kind = 'checking') <> 1 then
      raise exception 'Choose an account';
    end if;
    select a.id into v_account
      from public.accounts a
     where a.owner_id = v_owner and a.is_active and a.kind = 'checking';
  elsif not exists (select 1 from public.accounts a where a.id = v_account and a.owner_id = v_owner and a.is_active) then
    raise exception 'Unknown or inactive account';
  end if;

  if p_category_id is not null then
    select c.kind into v_kind from public.categories c where c.id = p_category_id and c.owner_id = v_owner;
    if v_kind is null then raise exception 'Unknown category'; end if;
    if v_kind = 'income' and p_amount < 0 then raise exception 'An income category needs money coming in'; end if;
  end if;

  if p_bill_occurrence_id is not null then
    if p_amount > 0 then raise exception 'A bill payment must be money going out'; end if;
    if not exists (select 1 from public.bill_occurrences o where o.id = p_bill_occurrence_id and o.owner_id = v_owner) then
      raise exception 'Unknown bill';
    end if;
  end if;
  if p_debt_id is not null then
    if p_amount > 0 then raise exception 'A debt payment must be money going out'; end if;
    if not exists (select 1 from public.debts d where d.id = p_debt_id and d.owner_id = v_owner) then
      raise exception 'Unknown debt';
    end if;
  end if;

  v_fp := public.txn_fingerprint(v_account, p_txn_date, p_amount, v_desc);
  select coalesce(max(t.occurrence), 0) + 1 into v_occ
    from public.transactions t where t.account_id = v_account and t.fingerprint = v_fp;

  insert into public.transactions
    (owner_id, account_id, txn_date, description_raw, merchant, amount, status, category_id, note,
     cleared, entry_source, bill_occurrence_id, debt_id, occurrence)
  values
    (v_owner, v_account, p_txn_date, v_desc, v_desc, p_amount, 'pending', p_category_id, v_note,
     coalesce(p_cleared, false), 'manual', p_bill_occurrence_id, p_debt_id, v_occ)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.update_manual_transaction(
  p_id                 uuid,
  p_amount             numeric,
  p_txn_date           date,
  p_merchant           text,
  p_category_id        uuid    default null,
  p_note               text    default null,
  p_cleared            boolean default false,
  p_bill_occurrence_id uuid    default null,
  p_debt_id            uuid    default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := public.assert_app_owner();
  r       public.transactions%rowtype;
  v_desc  text := nullif(btrim(coalesce(p_merchant, '')), '');
  v_note  text := nullif(btrim(coalesce(p_note, '')), '');
  v_today date := public.app_today();
  v_kind  text;
  v_fp    text;
  v_occ   int;
begin
  select * into r from public.transactions t where t.id = p_id and t.owner_id = v_owner for update;
  if not found then raise exception 'Transaction not found'; end if;
  if r.entry_source <> 'manual' then raise exception 'Only manual entries can be edited here'; end if;
  if r.reconciled then raise exception 'Claude already reconciled this transaction, so it is locked'; end if;

  if p_amount is null or p_amount = 0 then raise exception 'Enter an amount'; end if;
  if round(p_amount, 2) <> p_amount then raise exception 'Amounts have at most two decimal places'; end if;
  if abs(p_amount) > 1000000 then raise exception 'That amount is too large'; end if;
  if p_txn_date is null then raise exception 'Choose a date'; end if;
  if p_txn_date > v_today then raise exception 'The date cannot be in the future'; end if;
  if p_txn_date < v_today - 400 then raise exception 'The date is more than 400 days ago'; end if;
  if v_desc is null then raise exception 'Enter who you paid or who paid you'; end if;
  if length(v_desc) > 120 then raise exception 'The name is too long (120 characters max)'; end if;
  if v_note is not null and length(v_note) > 500 then raise exception 'The note is too long (500 characters max)'; end if;

  if p_category_id is not null then
    select c.kind into v_kind from public.categories c where c.id = p_category_id and c.owner_id = v_owner;
    if v_kind is null then raise exception 'Unknown category'; end if;
    if v_kind = 'income' and p_amount < 0 then raise exception 'An income category needs money coming in'; end if;
  end if;
  if p_bill_occurrence_id is not null then
    if p_amount > 0 then raise exception 'A bill payment must be money going out'; end if;
    if not exists (select 1 from public.bill_occurrences o where o.id = p_bill_occurrence_id and o.owner_id = v_owner) then
      raise exception 'Unknown bill';
    end if;
  end if;
  if p_debt_id is not null then
    if p_amount > 0 then raise exception 'A debt payment must be money going out'; end if;
    if not exists (select 1 from public.debts d where d.id = p_debt_id and d.owner_id = v_owner) then
      raise exception 'Unknown debt';
    end if;
  end if;

  v_fp := public.txn_fingerprint(r.account_id, p_txn_date, p_amount, v_desc);
  select coalesce(max(t.occurrence), 0) + 1 into v_occ
    from public.transactions t
   where t.account_id = r.account_id and t.fingerprint = v_fp and t.id <> p_id;

  update public.transactions t
     set amount = p_amount, txn_date = p_txn_date, description_raw = v_desc, merchant = v_desc,
         category_id = p_category_id, note = v_note, cleared = coalesce(p_cleared, false),
         bill_occurrence_id = p_bill_occurrence_id, debt_id = p_debt_id, occurrence = v_occ
   where t.id = p_id;
  return p_id;
end;
$$;

create or replace function public.delete_manual_transaction(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := public.assert_app_owner();
  r       public.transactions%rowtype;
begin
  select * into r from public.transactions t where t.id = p_id and t.owner_id = v_owner for update;
  if not found then raise exception 'Transaction not found'; end if;
  if r.entry_source <> 'manual' then raise exception 'Only manual entries can be deleted here'; end if;
  if r.reconciled then raise exception 'Claude already reconciled this transaction, so it is locked'; end if;
  delete from public.transactions where id = p_id;
end;
$$;

create or replace function public.set_transaction_cleared(p_id uuid, p_cleared boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := public.assert_app_owner();
  r       public.transactions%rowtype;
begin
  select * into r from public.transactions t where t.id = p_id and t.owner_id = v_owner for update;
  if not found then raise exception 'Transaction not found'; end if;
  if r.reconciled and not coalesce(p_cleared, false) then
    raise exception 'A reconciled transaction stays cleared';
  end if;
  update public.transactions set cleared = coalesce(p_cleared, false) where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2c. Claude-only reconciliation (not granted to authenticated/anon)
-- Use after matching a screenshot to existing rows. Post pending rows first (commit_screenshot_import).
-- ---------------------------------------------------------------------------
create or replace function public.reconcile_transactions(p_ids uuid[])
returns int
language plpgsql
set search_path = ''
as $$
declare n int;
begin
  update public.transactions t
     set reconciled = true, reconciled_at = now(), cleared = (t.cleared or t.status = 'posted')
   where t.id = any (p_ids) and not t.reconciled;
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function public.unreconcile_transactions(p_ids uuid[])
returns int
language plpgsql
set search_path = ''
as $$
declare n int;
begin
  update public.transactions t set reconciled = false, reconciled_at = null
   where t.id = any (p_ids) and t.reconciled;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Virtual envelopes
-- ---------------------------------------------------------------------------
create table public.envelopes (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null default public.app_owner_id(),
  kind       text not null check (kind in ('rainy_day', 'locked_savings')),
  name       text not null,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, kind)
);
comment on table public.envelopes is
  'Virtual savings. rainy_day: held back from spending but suggested when a pay period is short. locked_savings: never used by the forecast. No real money moves.';

create table public.envelope_moves (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default public.app_owner_id(),
  envelope_id uuid not null references public.envelopes(id) on delete cascade,
  move_date   date not null default public.app_today(),
  amount      numeric(12,2) not null check (amount <> 0),
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on column public.envelope_moves.amount is 'positive = money set aside into the envelope, negative = moved back to spendable cash';
create index envelope_moves_envelope_idx on public.envelope_moves (envelope_id, move_date);

create trigger set_updated_at before update on public.envelopes
  for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.envelope_moves
  for each row execute function public.set_updated_at();

alter table public.envelopes      enable row level security;
alter table public.envelope_moves enable row level security;
create policy "owner can read" on public.envelopes
  for select to authenticated using (owner_id = (select auth.uid()));
create policy "owner can read" on public.envelope_moves
  for select to authenticated using (owner_id = (select auth.uid()));
revoke all on public.envelopes, public.envelope_moves from anon, authenticated, public;
grant select on public.envelopes, public.envelope_moves to authenticated;

insert into public.envelopes (owner_id, kind, name)
select s.owner_id, k.kind, k.name
  from public.app_settings s
 cross join (values ('rainy_day', 'Rainy-day fund'), ('locked_savings', 'Locked savings')) as k(kind, name)
 where s.id
on conflict (owner_id, kind) do nothing;

create view public.v_envelopes with (security_invoker = true) as
select e.id, e.kind, e.name, e.is_active,
       coalesce(sum(m.amount), 0)::numeric(12,2) as balance,
       max(m.move_date)                          as last_move_date,
       count(m.id)::int                          as move_count
from public.envelopes e
left join public.envelope_moves m on m.envelope_id = e.id
group by e.id;

create view public.v_envelope_moves with (security_invoker = true) as
select m.id, m.envelope_id, e.kind, e.name as envelope_name, m.move_date, m.amount, m.note, m.created_at,
       sum(m.amount) over (partition by m.envelope_id order by m.move_date, m.created_at, m.id)::numeric(12,2) as balance_after
from public.envelope_moves m
join public.envelopes e on e.id = m.envelope_id;

-- Move money into (positive) or out of (negative) an envelope. Returns the new envelope balance.
create or replace function public.move_envelope_money(
  p_envelope_id uuid, p_amount numeric, p_note text default null, p_move_date date default null)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner   uuid := public.assert_app_owner();
  v_env     public.envelopes%rowtype;
  v_note    text := nullif(btrim(coalesce(p_note, '')), '');
  v_date    date := coalesce(p_move_date, public.app_today());
  v_bal     numeric;
  v_cash    numeric;
  v_all     numeric;
begin
  select * into v_env from public.envelopes e where e.id = p_envelope_id and e.owner_id = v_owner for update;
  if not found or not v_env.is_active then raise exception 'Unknown or inactive envelope'; end if;
  if p_amount is null or p_amount = 0 then raise exception 'Enter an amount'; end if;
  if round(p_amount, 2) <> p_amount then raise exception 'Amounts have at most two decimal places'; end if;
  if abs(p_amount) > 1000000 then raise exception 'That amount is too large'; end if;
  if v_date > public.app_today() then raise exception 'The date cannot be in the future'; end if;
  if v_note is not null and length(v_note) > 500 then raise exception 'The note is too long (500 characters max)'; end if;

  select coalesce(sum(m.amount), 0) into v_bal from public.envelope_moves m where m.envelope_id = v_env.id;
  if p_amount < 0 and v_bal + p_amount < 0 then
    raise exception 'Only % is in %', v_bal, v_env.name;
  end if;
  if p_amount > 0 then
    select coalesce(sum(ab.estimated_balance), 0) into v_cash
      from public.v_account_balances ab
     where ab.is_active and ab.kind in ('checking', 'savings', 'cash');
    select coalesce(sum(m.amount), 0) into v_all
      from public.envelope_moves m join public.envelopes e on e.id = m.envelope_id where e.is_active;
    if v_all + p_amount > v_cash then
      raise exception 'Envelopes cannot hold more than the cash you have (%)', v_cash;
    end if;
  end if;

  insert into public.envelope_moves (owner_id, envelope_id, move_date, amount, note)
  values (v_owner, v_env.id, v_date, p_amount, v_note);
  return v_bal + p_amount;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Forecast: envelope money is not spendable cash
-- Same signature and columns as 20261112190000; only the `cash` CTE gains the envelope subtraction.
-- ---------------------------------------------------------------------------
create or replace function public.pay_period_forecast(p_periods integer default 7, p_lookahead integer default 6)
 returns table(period_index integer, period_start date, period_end date, next_pay_date date, is_current boolean,
               expected_net numeric, income_in numeric, obligations numeric, starting_cash numeric, cash_as_of date,
               low_balance_floor numeric, safe_to_spend numeric, max_safe_to_spend numeric, hold_for_later numeric,
               carry_out numeric, binding_date date, binding_balance numeric, shortfall boolean, income_received boolean,
               cash_before_spending numeric, next_income numeric, next_obligations numeric, next_draw numeric,
               next_period_end date)
 language sql
 stable
 set search_path to ''
as $function$
  with recursive cfg as (
    select public.app_today() as today,
           coalesce((select s.low_balance_threshold from public.app_settings s where s.id), 0) as floor
  ),
  cash as (
    -- cash already reserved in set-aside envelopes is not spendable (this period's contribution is
    -- excluded: it is modelled as an outflow at payday). Rainy-day and locked-savings envelopes are
    -- also set apart: neither is spendable here; a short period only gets a suggested rainy-day draw.
    select coalesce(sum(ab.estimated_balance), 0)
             - coalesce((select sum(greatest(pos.balance - pos.current_contribution, 0))
                           from public.set_asides sa
                           cross join lateral public.set_aside_position(sa.id) pos
                          where sa.is_active), 0)
             - coalesce((select sum(m.amount)
                           from public.envelope_moves m
                           join public.envelopes e on e.id = m.envelope_id
                          where e.is_active), 0) as bal,
           min(ab.last_snapshot_date) as as_of
    from public.v_account_balances ab
    where ab.is_active and ab.kind in ('checking', 'savings', 'cash')
  ),
  cur as (
    select max(pd.pay_date) as d from cfg, public.pay_dates(cfg.today - 70, cfg.today) pd
  ),
  starts as (
    select x.pay_date, (row_number() over (order by x.pay_date))::int as k,
           lead(x.pay_date) over (order by x.pay_date) as nxt
    from (select distinct pd.pay_date
            from cur, public.pay_dates(cur.d, cur.d + 14 * (p_periods + p_lookahead + 2)) pd) x
  ),
  periods as (
    select s.k, s.pay_date, s.nxt, p.is_current, p.expected_net, p.items
    from starts s
    cross join lateral public.paycheck_plan(s.pay_date) p
    where s.nxt is not null and s.k <= p_periods + p_lookahead
  ),
  ev as (
    select pr.k,
           greatest(case when it->>'type' in ('income', 'bill', 'debt_minimum')
                         then (it->>'date')::date else pr.pay_date end, cfg.today) as ev_date,
           case when it->>'type' = 'income' then (it->>'amount')::numeric
                else -(it->>'amount')::numeric end as amount,
           it->>'type' as kind,
           it->>'name' as name,
           (it->>'type' = 'income' and exists (
              select 1
              from public.income_sources src
              join public.transactions t on t.account_id = src.deposit_account_id
              where src.id = (it->>'id')::uuid
                and t.amount >= 0.5 * (it->>'amount')::numeric
                and t.txn_date between (it->>'date')::date - 3 and (it->>'date')::date + 3)) as received
    from periods pr
    cross join cfg
    cross join lateral jsonb_array_elements(pr.items) it
  ),
  path as (
    -- same day: starting anchor, then deposits, then bills
    select e.k, e.ev_date, e.amount,
           row_number() over (order by e.ev_date,
                                       case when e.kind = 'start' then -1 when e.amount >= 0 then 0 else 1 end,
                                       e.k, e.name) as seq
    from (select ev.k, ev.ev_date, ev.amount, ev.kind, ev.name from ev where not ev.received
          union all
          select 0, cfg.today, 0, 'start', '' from cfg) e
  ),
  bal as (
    select p.ev_date, p.seq, cash.bal + sum(p.amount) over (order by p.seq) as balance
    from path p, cash
  ),
  per as (
    select pr.k, pr.pay_date, pr.nxt, pr.is_current, pr.expected_net,
           (select min(b.balance) from bal b
             where b.seq > 1 and b.ev_date >= greatest(pr.pay_date, cfg.today)) as m,
           (select b.ev_date from bal b
             where b.seq > 1 and b.ev_date >= greatest(pr.pay_date, cfg.today)
             order by b.balance, b.seq limit 1) as binding_date,
           (select b.balance from bal b where b.ev_date < pr.nxt order by b.seq desc limit 1) as bal_end,
           coalesce((select sum(e.amount) from ev e where e.k = pr.k and e.amount > 0 and not e.received), 0) as income_in,
           coalesce((select -sum(e.amount) from ev e where e.k = pr.k and e.amount < 0), 0) as obligations,
           exists (select 1 from ev e where e.k = pr.k and e.kind = 'income' and e.received) as income_received
    from periods pr, cfg
  ),
  a as (
    -- A_k: cumulative spending allowed through period k. With no events left (end of horizon)
    -- carry the previous bound forward rather than inventing room.
    select per.k, coalesce(per.m, per.bal_end) - cfg.floor as a from per, cfg
  ),
  lvl (k, c_prev, l) as (
    select 1, 0::numeric,
           (select min((a.a - 0) / (a.k - 1 + 1)) from a where a.k >= 1)
    union all
    select r.k + 1, r.c_prev + r.l,
           (select min((a.a - (r.c_prev + r.l)) / (a.k - (r.k + 1) + 1)) from a where a.k >= r.k + 1)
    from lvl r
    where r.k < (select max(k) from a)
  ),
  calc as (
    select per.*, cfg.floor, cash.bal as start_bal, cash.as_of, a.a,
           lvl.l, lvl.c_prev,
           per.bal_end - (lvl.c_prev + lvl.l) as carry
    from per
    join a on a.k = per.k
    join lvl on lvl.k = per.k
    cross join cfg cross join cash
  ),
  fin as (
    -- window functions run before the period_index filter below so the last returned period
    -- still sees the period that follows it
    select c.*,
           lag(c.carry) over (order by c.k) as prev_carry,
           lead(c.income_in) over (order by c.k) as nx_income,
           lead(c.obligations) over (order by c.k) as nx_obligations,
           lead(c.nxt) over (order by c.k) as nx_nxt
    from calc c
  )
  select c.k, c.pay_date, c.nxt - 1, c.nxt, c.is_current,
         c.expected_net, round(c.income_in, 2), round(c.obligations, 2),
         round(c.start_bal, 2), c.as_of, c.floor,
         round(c.l, 2),
         round(c.a - c.c_prev, 2),
         round(c.carry - coalesce(c.prev_carry, c.start_bal), 2),
         round(c.carry, 2),
         c.binding_date, round(c.m, 2),
         c.k = 1 and c.a < 0,
         c.income_received,
         round(c.carry + c.l, 2),
         round(c.nx_income, 2),
         round(c.nx_obligations, 2),
         round(c.nx_obligations - c.nx_income, 2),
         c.nx_nxt - 1
  from fin c
  where c.k <= p_periods
  order by c.k;
$function$;

-- Suggested rainy-day draw for the current pay period (nothing is moved automatically).
-- gap_to_floor = how far the projected low point sits below the minimum balance with zero extra spending.
create view public.v_rainy_day_suggestion with (security_invoker = true) as
select e.id as envelope_id,
       e.balance as rainy_balance,
       f.binding_date,
       f.binding_balance,
       f.low_balance_floor,
       g.gap as gap_to_floor,
       least(e.balance, g.gap) as suggested_draw,
       g.gap - least(e.balance, g.gap) as remaining_gap
from public.v_envelopes e
cross join lateral (
  select x.binding_date, x.binding_balance, x.low_balance_floor
    from public.v_pay_period_forecast x
   where x.is_current
   limit 1) f
cross join lateral (
  select greatest(f.low_balance_floor - coalesce(f.binding_balance, f.low_balance_floor), 0) as gap) g
where e.kind = 'rainy_day' and e.is_active;

-- ---------------------------------------------------------------------------
-- 5. v_transactions: append the new columns (existing column order is unchanged)
-- ---------------------------------------------------------------------------
create or replace view public.v_transactions with (security_invoker = true) as
select
  t.id,
  t.txn_date,
  date_trunc('month', t.txn_date::timestamp)::date as month,
  t.description_raw,
  t.merchant,
  t.amount,
  t.status,
  t.account_id,
  a.name  as account_name,
  a.kind  as account_kind,
  t.category_id,
  c.name  as category_name,
  c.parent_name as category_parent,
  c.kind  as category_kind,
  t.tags,
  t.needs_review,
  t.review_question,
  t.bill_occurrence_id,
  t.debt_id,
  t.note,
  t.import_batch_id,
  t.occurrence,
  t.created_at,
  t.cleared,
  t.reconciled,
  t.reconciled_at,
  t.entry_source
from public.transactions t
join public.accounts a on a.id = t.account_id
left join public.categories c on c.id = t.category_id;

-- ---------------------------------------------------------------------------
-- 6. Privileges
-- ---------------------------------------------------------------------------
revoke all on public.v_envelopes, public.v_envelope_moves, public.v_rainy_day_suggestion from anon, public;
grant select on public.v_envelopes, public.v_envelope_moves, public.v_rainy_day_suggestion to authenticated;

revoke all on function public.pay_period_forecast(integer, integer) from public, anon;
grant execute on function public.pay_period_forecast(integer, integer) to authenticated, service_role;

revoke execute on function
  public.is_web_session(), public.assert_app_owner(), public.guard_transaction_reconciliation(),
  public.reconcile_transactions(uuid[]), public.unreconcile_transactions(uuid[])
  from public, anon, authenticated;

revoke execute on function
  public.add_manual_transaction(numeric, date, text, uuid, uuid, text, boolean, uuid, uuid),
  public.update_manual_transaction(uuid, numeric, date, text, uuid, text, boolean, uuid, uuid),
  public.delete_manual_transaction(uuid),
  public.set_transaction_cleared(uuid, boolean),
  public.move_envelope_money(uuid, numeric, text, date)
  from public, anon;
grant execute on function
  public.add_manual_transaction(numeric, date, text, uuid, uuid, text, boolean, uuid, uuid),
  public.update_manual_transaction(uuid, numeric, date, text, uuid, text, boolean, uuid, uuid),
  public.delete_manual_transaction(uuid),
  public.set_transaction_cleared(uuid, boolean),
  public.move_envelope_money(uuid, numeric, text, date)
  to authenticated;
