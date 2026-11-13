-- Create and edit set-asides from the web app and the Claude chat.
--
-- A set-aside (public.set_asides) is a per-paycheck reservation with a rollover balance; it is not an
-- envelope. Its balance stays derived (set_aside_position / v_set_asides); these functions only store the
-- settings. There is no delete: pausing sets is_active = false, so the history and old transactions'
-- set_aside_id links stay intact. A paused set-aside takes nothing from paychecks and no longer holds back
-- its balance in the forecast (both already filter on is_active).
--
-- 1. Table rules: names trimmed, 1-60 chars, unique (case-insensitive) among the owner's active
--    set-asides; a category can feed at most one active set-aside (two would both draw the same spending).
-- 2. create_set_aside(...) and update_set_aside(..., p_is_active). Owner check: app_owner_for_write()
--    from 20261113040000 (assert_app_owner() for web requests; the configured owner for the chat's direct
--    database session). Amounts: at most 2 decimals, per_paycheck >= 0, cap null or >= 0, opening balance
--    within +/- 1,000,000. A new start_date must be within a year of today (a stored one is kept as is).
--    Category must be the owner's.
-- 3. v_set_asides gains opening_balance (appended) for the edit form.
-- Atomicity: expected to run as one transaction via apply_migration; every step is also re-runnable.

-- ---------------------------------------------------------------------------
-- 1. Table rules
-- ---------------------------------------------------------------------------
alter table public.set_asides drop constraint if exists set_asides_name_check;
alter table public.set_asides add constraint set_asides_name_check
  check (name = btrim(name) and char_length(name) between 1 and 60);
create unique index if not exists set_asides_active_name_per_owner on public.set_asides (owner_id, lower(name))
  where is_active;
create unique index if not exists set_asides_one_active_per_category on public.set_asides (category_id)
  where is_active and category_id is not null;

-- ---------------------------------------------------------------------------
-- 2. Validation shared by create and update (internal; not callable by the API roles)
-- ---------------------------------------------------------------------------
create or replace function public.set_aside_input_check(
  p_owner uuid, p_id uuid, p_name text, p_per_paycheck numeric, p_cap numeric, p_start_date date,
  p_opening_balance numeric, p_category_id uuid, p_is_active boolean)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_name  text := btrim(coalesce(p_name, ''));
  v_other text;
begin
  if v_name = '' then raise exception 'Enter a name'; end if;
  if char_length(v_name) > 60 then raise exception 'Names are at most 60 characters'; end if;

  if p_per_paycheck is null then raise exception 'Enter an amount per paycheck (0 is allowed)'; end if;
  if p_per_paycheck < 0 then raise exception 'The amount per paycheck cannot be negative'; end if;
  if round(p_per_paycheck, 2) <> p_per_paycheck then raise exception 'Amounts have at most two decimal places'; end if;
  if p_per_paycheck > 1000000 then raise exception 'That amount is too large'; end if;

  if p_cap is not null then
    if p_cap < 0 then raise exception 'The cap cannot be negative'; end if;
    if round(p_cap, 2) <> p_cap then raise exception 'Amounts have at most two decimal places'; end if;
    if p_cap > 1000000 then raise exception 'That amount is too large'; end if;
  end if;

  if p_opening_balance is null then raise exception 'Enter a starting balance (0 is allowed)'; end if;
  if round(p_opening_balance, 2) <> p_opening_balance then raise exception 'Amounts have at most two decimal places'; end if;
  if abs(p_opening_balance) > 1000000 then raise exception 'That amount is too large'; end if;

  if p_start_date is null then raise exception 'Enter a start date'; end if;
  -- New dates must be within a year of today; an existing set-aside keeps its stored date (so an old one can
  -- still be edited or paused).
  if (p_start_date < public.app_today() - 366 or p_start_date > public.app_today() + 366)
     and p_start_date is distinct from (select sa.start_date from public.set_asides sa where sa.id = p_id) then
    raise exception 'Pick a start date within a year of today';
  end if;

  if p_category_id is not null
     and not exists (select 1 from public.categories c where c.id = p_category_id and c.owner_id = p_owner) then
    raise exception 'Unknown category';
  end if;

  if p_is_active then
    if exists (select 1 from public.set_asides sa
                where sa.owner_id = p_owner and sa.is_active and sa.id is distinct from p_id
                  and lower(sa.name) = lower(v_name)) then
      raise exception 'You already have a set-aside called %', v_name;
    end if;
    if p_category_id is not null then
      select sa.name into v_other from public.set_asides sa
       where sa.owner_id = p_owner and sa.is_active and sa.category_id = p_category_id
         and sa.id is distinct from p_id
       limit 1;
      if found then
        raise exception 'That category already draws from the set-aside %', v_other;
      end if;
    end if;
  end if;
  return v_name;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Write functions
-- ---------------------------------------------------------------------------
create or replace function public.create_set_aside(
  p_name text, p_per_paycheck numeric, p_cap numeric default null, p_start_date date default null,
  p_opening_balance numeric default 0, p_category_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := public.app_owner_for_write();
  v_start date := coalesce(p_start_date, public.app_today());
  v_open  numeric := coalesce(p_opening_balance, 0);
  v_name  text;
  v_id    uuid;
begin
  v_name := public.set_aside_input_check(v_owner, null, p_name, p_per_paycheck, p_cap, v_start, v_open,
                                         p_category_id, true);
  insert into public.set_asides (owner_id, name, per_paycheck, cap, start_date, opening_balance, category_id, is_active)
  values (v_owner, v_name, p_per_paycheck, p_cap, v_start, v_open, p_category_id, true)
  returning id into v_id;
  return v_id;
end;
$$;
comment on function public.create_set_aside(text, numeric, numeric, date, numeric, uuid) is
  'Create an active set-aside. start_date defaults to today, opening_balance to 0. The balance is derived (v_set_asides).';

create or replace function public.update_set_aside(
  p_id uuid, p_name text, p_per_paycheck numeric, p_cap numeric, p_start_date date,
  p_opening_balance numeric, p_category_id uuid, p_is_active boolean)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := public.app_owner_for_write();
  v_sa    public.set_asides%rowtype;
  v_name  text;
begin
  select * into v_sa from public.set_asides sa where sa.id = p_id and sa.owner_id = v_owner for update;
  if not found then raise exception 'Unknown set-aside'; end if;
  if p_is_active is null then raise exception 'Choose active or paused'; end if;
  v_name := public.set_aside_input_check(v_owner, v_sa.id, p_name, p_per_paycheck, p_cap, p_start_date,
                                         p_opening_balance, p_category_id, p_is_active);
  update public.set_asides
     set name = v_name, per_paycheck = p_per_paycheck, cap = p_cap, start_date = p_start_date,
         opening_balance = p_opening_balance, category_id = p_category_id, is_active = p_is_active
   where id = v_sa.id;
  return v_sa.id;
end;
$$;
comment on function public.update_set_aside(uuid, text, numeric, numeric, date, numeric, uuid, boolean) is
  'Edit, pause (p_is_active = false) or resume a set-aside. Set-asides are never deleted.';

-- ---------------------------------------------------------------------------
-- 4. v_set_asides: append opening_balance (existing columns unchanged)
-- ---------------------------------------------------------------------------
create or replace view public.v_set_asides with (security_invoker = true) as
select sa.id, sa.name, sa.per_paycheck, sa.cap, sa.is_active, sa.start_date,
       sa.category_id, c.name as category_name,
       pos.balance, pos.current_contribution,
       case when sa.cap is null then null else greatest(sa.cap - pos.balance, 0) end as room_left,
       coalesce(pos.balance >= sa.cap, false) as at_cap,
       sa.opening_balance
from public.set_asides sa
left join public.categories c on c.id = sa.category_id
cross join lateral public.set_aside_position(sa.id) pos;
alter view public.v_set_asides set (security_invoker = true);

-- ---------------------------------------------------------------------------
-- 5. Privileges
-- ---------------------------------------------------------------------------
revoke execute on function public.set_aside_input_check(uuid, uuid, text, numeric, numeric, date, numeric, uuid, boolean)
  from public, anon, authenticated;
revoke execute on function
  public.create_set_aside(text, numeric, numeric, date, numeric, uuid),
  public.update_set_aside(uuid, text, numeric, numeric, date, numeric, uuid, boolean)
  from public, anon;
grant execute on function
  public.create_set_aside(text, numeric, numeric, date, numeric, uuid),
  public.update_set_aside(uuid, text, numeric, numeric, date, numeric, uuid, boolean)
  to authenticated;
revoke all on public.v_set_asides from anon, public;
grant select on public.v_set_asides to authenticated;
