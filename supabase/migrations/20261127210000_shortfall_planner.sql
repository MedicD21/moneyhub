-- Shortfall planner: plan extra overtime (OT) and spending money per paycheck against the forecast.
--
-- 1. public.shortfall_plans: one saved plan per owner (a jsonb list of {pay_date, ot_hours, spend}).
--    SELECT-only for the signed-in user (RLS); the only write is save_shortfall_plan() below.
-- 2. public.shortfall_plan_entries(jsonb): internal validation shared by the read and write functions.
-- 3. public.shortfall_plan_forecast(jsonb default null): READ-ONLY scenario. It layers the plan on top of
--    daily_balance_forecast() (nothing in pay_period_forecast or paycheck_plan changes) and returns one
--    summary object and one row per paycheck period. p_paychecks null = use the saved plan, otherwise the
--    unsaved draft passed in. The browser only displays what it returns.
--      * OT: ot_hours x app_settings.extra_hour_net, deposited on that paycheck's date, lifting every later
--        balance. Only a paycheck that has not been received and has no actual net in pay_date_overrides
--        takes OT. Once the real net is entered it already includes the OT, so the estimate is ignored
--        (ot_replaced) and never added on top.
--      * Spending: reserved on the first day of that paycheck's period (today for the current period), so
--        the plan errs on the cautious side. It models food, gas and similar spending that the scheduled
--        forecast leaves out.
--      * Suggestions: working forward, each editable paycheck gets the extra whole hours that cover its
--        window's dip below the low-balance floor, counting earlier suggestions. A dip in a window that can
--        no longer receive OT (a paycheck already in the past) is reported as unfixable_shortfall.
-- 4. public.save_shortfall_plan(jsonb): the thirteenth owner-checked write function (approved by Dustin on
--    2026-11-27). It stores only the plan; zero rows are dropped.
-- Atomicity: expected to run as one transaction via apply_migration.

-- ---------------------------------------------------------------------------
-- 1. Table
-- ---------------------------------------------------------------------------
create table public.shortfall_plans (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null unique default public.app_owner_id(),
  paychecks  jsonb not null default '[]'::jsonb check (jsonb_typeof(paychecks) = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.shortfall_plans is 'One saved shortfall plan per owner: a jsonb list of {pay_date, ot_hours, spend}. Written only by save_shortfall_plan().';
alter table public.shortfall_plans enable row level security;
create policy "owner can read" on public.shortfall_plans for select to authenticated
  using (owner_id = (select auth.uid()));
revoke all on public.shortfall_plans from anon, authenticated;
grant select on public.shortfall_plans to authenticated;
create trigger set_updated_at before update on public.shortfall_plans
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. Input validation (pure; shared by the read and write functions)
-- ---------------------------------------------------------------------------
create or replace function public.shortfall_plan_entries(p_paychecks jsonb)
returns table (entry_date date, ot_hours numeric, spend numeric)
language plpgsql
stable
set search_path = ''
as $$
declare
  e     jsonb;
  d     date;
  h     numeric;
  s     numeric;
  seen  date[] := '{}';
begin
  if p_paychecks is null then return; end if;
  if jsonb_typeof(p_paychecks) <> 'array' then raise exception 'The plan must be a list of paychecks'; end if;
  if jsonb_array_length(p_paychecks) > 60 then raise exception 'A plan holds at most 60 paychecks'; end if;
  for e in select value from jsonb_array_elements(p_paychecks) loop
    if jsonb_typeof(e) <> 'object' then raise exception 'Each paycheck in the plan must be an object'; end if;
    begin
      d := (e->>'pay_date')::date;
    exception when others then
      raise exception 'Each paycheck needs a valid pay date';
    end;
    if d is null then raise exception 'Each paycheck needs a valid pay date'; end if;
    begin
      h := coalesce((e->>'ot_hours')::numeric, 0);
      s := coalesce((e->>'spend')::numeric, 0);
    exception when others then
      raise exception 'Hours and spending must be numbers';
    end;
    if d = any (seen) then raise exception 'A pay date can appear only once in the plan'; end if;
    seen := seen || d;
    if h < 0 or s < 0 then raise exception 'Hours and spending cannot be negative'; end if;
    if h > 120 then raise exception 'Overtime is at most 120 hours per paycheck'; end if;
    if s > 100000 then raise exception 'That spending amount is too large'; end if;
    if round(h, 2) <> h or round(s, 2) <> s then raise exception 'Hours and amounts have at most two decimal places'; end if;
    return query select d, h, s;
  end loop;
end;
$$;
comment on function public.shortfall_plan_entries(jsonb) is
  'Validates a shortfall plan list ({pay_date, ot_hours, spend}); raises a plain-language error or returns the rows.';

-- ---------------------------------------------------------------------------
-- 3. Read-only scenario
-- ---------------------------------------------------------------------------
create or replace function public.shortfall_plan_forecast(p_paychecks jsonb default null)
returns table (plan_summary jsonb, plan_periods jsonb)
language plpgsql
stable
set search_path = ''
as $fn$
declare
  v_today      date    := public.app_today();
  v_floor      numeric := coalesce((select s.low_balance_threshold from public.app_settings s where s.id), 0);
  v_net        numeric := coalesce((select s.extra_hour_net from public.app_settings s where s.id), 0);
  v_saved      jsonb;
  v_saved_at   timestamptz;
  v_input      jsonb;
  v_source     text;
  v_added      numeric := 0;
  v_sugg       integer;
  v_deficit    numeric;
  v_hours_sug  integer := 0;
  v_unfixable  numeric := 0;
  v_rows       jsonb   := '[]'::jsonb;
  v_hours_plan numeric := 0;
  v_ot_net     numeric := 0;
  v_spend      numeric := 0;
  v_low        numeric;
  v_low_date   date;
  v_base_low   numeric;
  v_base_date  date;
  r            record;
begin
  select sp.paychecks, sp.updated_at into v_saved, v_saved_at from public.shortfall_plans sp limit 1;
  if p_paychecks is null then
    v_input  := coalesce(v_saved, '[]'::jsonb);
    v_source := case when v_saved is null then 'none' else 'saved' end;
  else
    v_input  := p_paychecks;
    v_source := 'draft';
  end if;
  -- validate even when no row ends up matching a paycheck
  perform 1 from public.shortfall_plan_entries(v_input) limit 1;

  for r in
    with entries as (
      select e.entry_date as e_date, e.ot_hours as e_hours, e.spend as e_spend
      from public.shortfall_plan_entries(v_input) e
    ),
    daily as (
      select d.day, d.projected_balance as base from public.daily_balance_forecast(13, 6) d
    ),
    cur as (
      select max(pd.pay_date) as d from public.pay_dates(v_today - 70, v_today) pd
    ),
    starts as (
      select x.pay_date, (row_number() over (order by x.pay_date))::int as k,
             lead(x.pay_date) over (order by x.pay_date) as nxt
      from (select distinct pd.pay_date
              from cur, public.pay_dates(cur.d, cur.d + 14 * (13 + 6 + 2)) pd) x
    ),
    pp as (
      select s.k, s.pay_date, s.nxt, p.expected_net, p.is_current,
             inc.deposit_date, inc.income_amount, inc.received, inc.has_actual
      from starts s
      cross join lateral public.paycheck_plan(s.pay_date) p
      cross join lateral (
        select coalesce(min((it->>'date')::date), s.pay_date) as deposit_date,
               coalesce(sum((it->>'amount')::numeric), 0) as income_amount,
               coalesce(bool_or(exists (
                 select 1
                 from public.income_sources src
                 join public.transactions t on t.account_id = src.deposit_account_id
                 where src.id = (it->>'id')::uuid
                   and t.amount >= 0.5 * (it->>'amount')::numeric
                   and t.txn_date between (it->>'date')::date - 3 and (it->>'date')::date + 3)), false) as received,
               coalesce(bool_or(exists (
                 select 1 from public.pay_date_overrides ov
                 where ov.income_source_id = (it->>'id')::uuid
                   and ov.actual_date = (it->>'date')::date
                   and ov.actual_net is not null)), false) as has_actual
        from jsonb_array_elements(p.items) it
        where it->>'type' = 'income'
      ) inc
      where s.nxt is not null and s.k <= 13
    ),
    pc as (
      select pp.*,
             (pp.deposit_date > v_today and not pp.received and not pp.has_actual) as editable,
             (pp.nxt > v_today) as spend_open,
             coalesce(en.e_hours, 0) as ot_in,
             coalesce(en.e_spend, 0) as spend_in,
             greatest(pp.pay_date, v_today) as win_start,
             pp.nxt - 1 as win_end
      from pp
      left join entries en on en.e_date = pp.pay_date
    ),
    pc2 as (
      select pc.*,
             case when pc.editable then pc.ot_in else 0 end as ot_hours,
             case when pc.editable then round(pc.ot_in * v_net, 2) else 0 end as ot_net,
             case when pc.spend_open then pc.spend_in else 0 end as spend
      from pc
    ),
    adj as (
      select d.day, d.base,
             d.base
               + coalesce((select sum(q.ot_net) from pc2 q where q.deposit_date <= d.day), 0)
               - coalesce((select sum(q.spend) from pc2 q where q.win_start <= d.day), 0) as bal
      from daily d
    )
    select pc2.*,
           (select min(a.bal) from adj a where a.day between pc2.win_start and pc2.win_end) as low_balance,
           (select a.day from adj a where a.day between pc2.win_start and pc2.win_end
             order by a.bal, a.day limit 1) as low_date,
           (select min(a.base) from adj a where a.day between pc2.win_start and pc2.win_end) as base_low,
           (select a.day from adj a where a.day between pc2.win_start and pc2.win_end
             order by a.base, a.day limit 1) as base_low_date,
           (select min(a.bal) from adj a where a.day >= pc2.win_start) as min_from_here
    from pc2
    order by pc2.k
  loop
    if r.low_balance is null then continue; end if;
    v_deficit := greatest(v_floor - (r.low_balance + v_added), 0);
    v_sugg := 0;
    if r.editable then
      if v_deficit > 0 and v_net > 0 then v_sugg := ceil(v_deficit / v_net)::integer; end if;
      v_added := v_added + v_sugg * v_net;
      v_hours_sug := v_hours_sug + v_sugg;
    else
      v_unfixable := v_unfixable + v_deficit;
    end if;

    v_hours_plan := v_hours_plan + r.ot_hours;
    v_ot_net := v_ot_net + r.ot_net;
    v_spend := v_spend + r.spend;
    if v_low is null or r.low_balance < v_low then v_low := r.low_balance; v_low_date := r.low_date; end if;
    if v_base_low is null or r.base_low < v_base_low then v_base_low := r.base_low; v_base_date := r.base_low_date; end if;

    v_rows := v_rows || jsonb_build_array(jsonb_build_object(
      'pay_date', r.pay_date,
      'period_end', r.nxt - 1,
      'next_pay_date', r.nxt,
      'is_current', r.is_current,
      'status', case when r.received then 'received' when r.has_actual then 'actual'
                     when r.editable then 'open' else 'past' end,
      'expected_net', r.expected_net,
      'income_amount', r.income_amount,
      'ot_editable', r.editable,
      'ot_hours', r.ot_hours,
      'ot_net', r.ot_net,
      'ot_replaced', (not r.editable and r.ot_in > 0),
      'spend_editable', r.spend_open,
      'spend', r.spend,
      'low_balance', r.low_balance,
      'low_date', r.low_date,
      'baseline_low_balance', r.base_low,
      'shortfall', greatest(v_floor - r.low_balance, 0),
      'spend_room', greatest(r.min_from_here - v_floor, 0),
      'suggested_hours', case when r.editable then v_sugg end,
      'suggested_net', case when r.editable then round(v_sugg * v_net, 2) end,
      'unfixable_shortfall', case when r.editable then 0 else v_deficit end));
  end loop;

  plan_summary := jsonb_build_object(
    'today', v_today,
    'floor', v_floor,
    'extra_hour_net', v_net,
    'source', v_source,
    'saved_at', v_saved_at,
    'saved_plan', coalesce(v_saved, '[]'::jsonb),
    'hours_planned', v_hours_plan,
    'ot_net_planned', v_ot_net,
    'spend_planned', v_spend,
    'lowest_balance', v_low,
    'lowest_date', v_low_date,
    'baseline_lowest_balance', v_base_low,
    'baseline_lowest_date', v_base_date,
    'baseline_shortfall', greatest(v_floor - coalesce(v_base_low, v_floor), 0),
    'remaining_shortfall', greatest(v_floor - coalesce(v_low, v_floor), 0),
    'suggested_hours_total', v_hours_sug,
    'suggested_net_total', round(v_hours_sug * v_net, 2),
    'unfixable_shortfall', v_unfixable);
  plan_periods := v_rows;
  return next;
end;
$fn$;
comment on function public.shortfall_plan_forecast(jsonb) is
  'Read-only shortfall planner. Layers planned OT (extra_hour_net per hour, on that paycheck) and planned spending onto daily_balance_forecast and returns a summary plus one row per paycheck period, with suggested extra hours. p_paychecks null = saved plan.';

-- ---------------------------------------------------------------------------
-- 4. The write
-- ---------------------------------------------------------------------------
create or replace function public.save_shortfall_plan(p_paychecks jsonb)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := public.app_owner_for_write();
  v_clean jsonb;
  v_at    timestamptz;
begin
  select coalesce(jsonb_agg(jsonb_build_object('pay_date', e.entry_date, 'ot_hours', e.ot_hours, 'spend', e.spend)
                            order by e.entry_date), '[]'::jsonb)
    into v_clean
  from public.shortfall_plan_entries(p_paychecks) e
  where e.ot_hours > 0 or e.spend > 0;

  insert into public.shortfall_plans (owner_id, paychecks) values (v_owner, v_clean)
  on conflict (owner_id) do update set paychecks = excluded.paychecks
  returning updated_at into v_at;
  return v_at;
end;
$$;
comment on function public.save_shortfall_plan(jsonb) is
  'Saves the owner''s shortfall plan (list of {pay_date, ot_hours, spend}); rows with zero hours and zero spending are dropped. Returns the save time.';

revoke all on function public.shortfall_plan_entries(jsonb) from public, anon;
revoke all on function public.shortfall_plan_forecast(jsonb) from public, anon;
revoke all on function public.save_shortfall_plan(jsonb) from public, anon;
grant execute on function public.shortfall_plan_entries(jsonb) to authenticated, service_role;
grant execute on function public.shortfall_plan_forecast(jsonb) to authenticated, service_role;
grant execute on function public.save_shortfall_plan(jsonb) to authenticated, service_role;
