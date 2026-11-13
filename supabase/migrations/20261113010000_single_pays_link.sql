-- One "Pays" link: the database decides transactions.debt_id.
--
-- Every debt has a payment bill (bills.debt_id), so the add/edit sheet showed debts twice and the two
-- RPC parameters were stored independently: picking only a debt bill left transactions.debt_id null, and a
-- bill could be linked to an unrelated debt. Now, when p_bill_occurrence_id belongs to a bill with
-- bills.debt_id set, the stored debt_id comes from the bill; a different p_debt_id is an error. A bill with
-- no debt keeps today's behavior, and p_debt_id alone (an extra payment toward a debt) still works.
-- Same signatures as 20261113000000, so grants carry over. Everything else is unchanged.
--
-- Also: v_upcoming_bills (select * from v_bill_status, expanded when it was created) gains the columns
-- appended to v_bill_status later (debt_id, end_date) so the sheet can tell which bills are debt bills.
-- create or replace may reset reloptions, so security_invoker is re-asserted.

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
  v_debt       uuid := p_debt_id;
  v_bill_debt  uuid;
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
    select b.debt_id into v_bill_debt
      from public.bill_occurrences o
      join public.bills b on b.id = o.bill_id
     where o.id = p_bill_occurrence_id and o.owner_id = v_owner;
    if not found then
      raise exception 'Unknown bill';
    end if;
    -- A bill that is a debt's payment schedule decides the debt: the stored debt_id always follows it.
    if v_bill_debt is not null then
      if p_debt_id is not null and p_debt_id <> v_bill_debt then
        raise exception 'That bill pays a different debt than the one selected';
      end if;
      v_debt := v_bill_debt;
    end if;
  end if;
  if v_debt is not null then
    if p_amount > 0 then raise exception 'A debt payment must be money going out'; end if;
    if not exists (select 1 from public.debts d where d.id = v_debt and d.owner_id = v_owner) then
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
     coalesce(p_cleared, false), 'manual', p_bill_occurrence_id, v_debt, v_occ)
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
  v_debt       uuid := p_debt_id;
  v_bill_debt  uuid;
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
    select b.debt_id into v_bill_debt
      from public.bill_occurrences o
      join public.bills b on b.id = o.bill_id
     where o.id = p_bill_occurrence_id and o.owner_id = v_owner;
    if not found then
      raise exception 'Unknown bill';
    end if;
    -- A bill that is a debt's payment schedule decides the debt: the stored debt_id always follows it.
    if v_bill_debt is not null then
      if p_debt_id is not null and p_debt_id <> v_bill_debt then
        raise exception 'That bill pays a different debt than the one selected';
      end if;
      v_debt := v_bill_debt;
    end if;
  end if;
  if v_debt is not null then
    if p_amount > 0 then raise exception 'A debt payment must be money going out'; end if;
    if not exists (select 1 from public.debts d where d.id = v_debt and d.owner_id = v_owner) then
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
         bill_occurrence_id = p_bill_occurrence_id, debt_id = v_debt, occurrence = v_occ
   where t.id = p_id;
  return p_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- v_upcoming_bills: pick up debt_id and end_date (appended after the existing columns)
-- ---------------------------------------------------------------------------
create or replace view public.v_upcoming_bills with (security_invoker = true) as
select *
from public.v_bill_status
where status in ('due','partial')
  and bill_is_active
  and due_date <= public.app_today() + 30;
alter view public.v_upcoming_bills set (security_invoker = true);
revoke all on public.v_upcoming_bills from anon, public;
grant select on public.v_upcoming_bills to authenticated;
