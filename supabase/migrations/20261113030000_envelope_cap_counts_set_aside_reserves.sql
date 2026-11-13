-- move_envelope_money: money already held by set-asides is not free to put in an envelope.
--
-- pay_period_forecast's starting cash subtracts two separate reserves from real cash
-- (checking + savings + cash accounts):
--   * set-aside balances (v_set_asides; balance minus this payday's contribution, which the forecast
--     books as an outflow on payday instead), and
--   * envelope balances (rainy-day fund + locked savings).
-- move_envelope_money only checked envelopes against real cash, so the same dollar could be reserved
-- by a set-aside and by an envelope, and starting cash could go below zero. Now a move in is rejected
-- when active envelopes + the move + positive set-aside balances would exceed real cash. Overspent
-- (negative) set-aside balances do not free up room. Moves out are unchanged.
--
-- Note: set-asides grow every payday by themselves, so the total can still pass real cash later; this
-- check only stops a move in from creating the overlap.
--
-- Naming: "envelope" means only the rainy-day fund and locked savings (public.envelopes). Comments in
-- 20261112180000_set_aside_rollover.sql and the pay_period_forecast body call set-asides "envelopes";
-- those are set-asides (public.set_asides). Applied migrations are not rewritten.
--
-- Same signature, so the existing grants (authenticated only) carry over. pay_period_forecast is unchanged.

create or replace function public.move_envelope_money(
  p_envelope_id uuid, p_amount numeric, p_note text default null, p_move_date date default null)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner    uuid := public.assert_app_owner();
  v_env      public.envelopes%rowtype;
  v_note     text := nullif(btrim(coalesce(p_note, '')), '');
  v_date     date := coalesce(p_move_date, public.app_today());
  v_bal      numeric;
  v_cash     numeric;
  v_all      numeric;
  v_reserved numeric;
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
    select coalesce(sum(greatest(pos.balance, 0)), 0) into v_reserved
      from public.set_asides sa
      cross join lateral public.set_aside_position(sa.id) pos
     where sa.is_active and sa.owner_id = v_owner;
    if v_all + v_reserved + p_amount > v_cash then
      raise exception 'Envelopes cannot hold more than the cash you have after set-asides (% free)',
        greatest(v_cash - v_reserved - v_all, 0);
    end if;
  end if;

  insert into public.envelope_moves (owner_id, envelope_id, move_date, amount, note)
  values (v_owner, v_env.id, v_date, p_amount, v_note);
  return v_bal + p_amount;
end;
$$;

comment on function public.move_envelope_money(uuid, numeric, text, date) is
  'Web write: move money into (+) or out of (-) the rainy-day fund or locked savings. A move in may not push envelopes plus set-aside balances above real cash.';
