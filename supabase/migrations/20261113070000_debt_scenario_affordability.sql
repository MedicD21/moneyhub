-- Decorate the existing read-only simulator. No table writes or forecast changes.
create or replace function public._debt_scenario_context(p_params jsonb, p_result jsonb)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_owner uuid := public.assert_app_owner(); v_today date := public.app_today();
  v_monthly jsonb; v_periods jsonb; v_rainy jsonb; v_defaults jsonb;
  v_peak numeric; v_from date; v_through date; v_flags integer; v_cash_flags integer;
  v_unfunded numeric := (p_result#>>'{summary,what_if_removed}')::numeric;
begin
  -- Chart totals and affordability arithmetic stay in PostgreSQL.
  select coalesce(jsonb_agg(to_jsonb(m) order by month),'[]') into v_monthly from (
    select value->>'month' month, sum((value->>'start')::numeric) opening_balance,
      sum((value->>'end')::numeric) balance, sum((value->>'payment')::numeric) payment,
      sum((value->>'minimum')::numeric) minimum, sum((value->>'interest')::numeric) interest,
      sum((value->>'fee')::numeric) fees
    from jsonb_array_elements(p_result->'schedule') group by 1
  ) m;
  select to_jsonb(r) into v_rainy from public.v_rainy_day_suggestion r limit 1;
  select jsonb_build_object('strategy',strategy,'extra_monthly',extra_monthly,
    'start_month',to_char(balances_as_of,'YYYY-MM'),'params',p_params - 'rollover' - 'start_month')
    into v_defaults from public.debt_plans where owner_id=v_owner and is_active;

  with forecast as materialized (
    select f.* from public.v_pay_period_forecast f
  ), monthly as (
    select (x->>'month'||'-01')::date m,
      -- Lump sums are checked on their requested dates, not spread a second time.
      greatest((x->>'payment')::numeric-(x->>'minimum')::numeric-
        coalesce((select sum((l->>'amount')::numeric)
          from jsonb_array_elements(coalesce(p_params->'lump_sums','[]')) l
          where to_char((l->>'date')::date,'YYYY-MM')=x->>'month'),0),0) extra
    from jsonb_array_elements(v_monthly) x
  ), items as (
    select f.period_index, it, coalesce(b.debt_id,
        case when it->>'type'='debt_minimum' then (it->>'id')::uuid end) debt_id,
      greatest(coalesce((it->>'date')::date,f.period_start),v_today) event_date
    from forecast f cross join lateral public.paycheck_plan(f.period_start) p
    cross join lateral jsonb_array_elements(p.items) it
    left join public.bills b on it->>'type'='bill' and b.id=(it->>'id')::uuid and b.owner_id=v_owner
  ), released as (
    select period_index, sum((it->>'amount')::numeric) amount from items i
    where it->>'type'='extra_debt' -- Already budgeted by the active plan: never charge twice.
      or (debt_id is not null and p_result#>>array['summary','per_debt_payoff_month',debt_id::text] < to_char(event_date,'YYYY-MM'))
      or exists(select 1 from jsonb_array_elements(coalesce(p_params->'drop_payment','[]')) d
        where (d->>'from_month'||'-01')::date <= event_date
          and ((d->>'kind'='debt' and d->>'debt_id'=i.debt_id::text)
            or (d->>'kind'='bill' and it->>'type'='bill' and lower(d->>'label')=lower(it->>'name'))))
    group by 1
  ), costs as (
    select f.*,
      round(coalesce((select sum(m.extra *
        greatest(least(f.period_end,(m.m+interval '1 month - 1 day')::date)-greatest(f.period_start,m.m,v_today)+1,0)::numeric /
        greatest((m.m+interval '1 month')::date-greatest(m.m,v_today),1)) from monthly m
        where m.m<=f.period_end and (m.m+interval '1 month')::date>greatest(f.period_start,v_today)),0),2) regular_extra,
      coalesce((select sum((l->>'amount')::numeric) from jsonb_array_elements(coalesce(p_params->'lump_sums','[]')) l
        where (l->>'date')::date between greatest(f.period_start,v_today) and f.period_end),0) lump_cash,
      coalesce(r.amount,0) released_obligations,
      -- Hypothetical income is available only in its actual pay period.
      coalesce((select sum((o->>'hours')::numeric * s.extra_hour_net)
        from jsonb_array_elements(coalesce(p_params->'overtime','[]')) o
        cross join public.app_settings s where s.id and s.owner_id=v_owner
          and (o->>'pay_date')::date between greatest(f.period_start,v_today) and f.period_end),0)
      + coalesce((select count(*) * (p_params#>>'{raise,extra_net_per_paycheck}')::numeric
        from public.pay_dates(greatest(f.period_start,v_today),f.period_end) pd
        join public.income_sources src on src.id=pd.income_source_id and src.owner_id=v_owner
        where pd.pay_date >= (p_params#>>'{raise,effective_date}')::date),0) added_income
    from forecast f left join released r using(period_index)
  ), net as (
    select c.*, regular_extra+lump_cash-released_obligations-added_income net_extra from costs c
  ), running as (
    select n.*,sum(net_extra) over(order by period_index) cumulative_extra from net n
  ), assessed as (
    select period_index, period_start, period_end, is_current, obligations baseline_obligations,
      cash_before_spending+obligations-(cumulative_extra-net_extra) available_cash,
      regular_extra,lump_cash,released_obligations,round(added_income,2) added_income,
      net_extra,cumulative_extra,low_balance_floor, max_safe_to_spend,
      cash_before_spending-cumulative_extra projected_cash,
      greatest(cumulative_extra-cash_before_spending,0) cash_gap,
      -- max_safe_to_spend protects the forecast's later/intraperiod low point.
      -- Negative savings are never used to promise more safety at an earlier low point.
      greatest(low_balance_floor-(cash_before_spending-cumulative_extra),
        cumulative_extra-max_safe_to_spend,0) gap_to_floor
    from running
  )
  select coalesce(jsonb_agg(to_jsonb(a) || jsonb_build_object(
      'flagged',gap_to_floor>0,'cash_shortfall',cash_gap>0) order by period_index),'[]'),
    coalesce(max(gap_to_floor),0), min(period_start),max(period_end),
    count(*) filter(where gap_to_floor>0),count(*) filter(where cash_gap>0)
    into v_periods,v_peak,v_from,v_through,v_flags,v_cash_flags from assessed a;

  return p_result || jsonb_build_object('monthly_balances',v_monthly,'defaults',v_defaults,
    'affordability',jsonb_build_object('as_of_date',v_today,'from_date',greatest(v_from,v_today),
      'through_date',v_through,'periods',v_periods,'flagged_periods',v_flags,'cash_shortfall_periods',v_cash_flags,
      'status',case when v_through is null then 'unavailable' when v_unfunded>0 then 'unfunded_what_if'
        when v_flags>0 then 'at_risk' else 'within_forecast' end,
      'peak_gap',v_peak,'unfunded_payoff',v_unfunded,
      'rainy_day',v_rainy,'suggested_draw',case when v_rainy is not null then least((v_rainy->>'rainy_balance')::numeric,v_peak) end,
      'remaining_gap',case when v_rainy is not null then greatest(v_peak-(v_rainy->>'rainy_balance')::numeric,0) else v_peak end,
      'full_plan_checked',false,
      'method','Monthly extras are spread across remaining calendar days. Lump sums use their requested dates and require existing cash. Raise and overtime income use actual pay periods. Previously paid-off minimums and stopped bills are credited once. Current planned spending and future cash buffers are protected. Rainy-day money is not included in available cash. Only displayed forecast periods are assessed; this is a conservative screen, not a daily cash forecast.'));
end;
$$;
revoke all on function public._debt_scenario_context(jsonb,jsonb) from public,anon,authenticated,service_role;

-- Preserve the validated simulation and all permissions; append read-only context.
-- Fail atomically if the installed source differs instead of silently patching nothing.
do $$
declare src text;
begin
  src := pg_get_functiondef('public.simulate_debt_plan(jsonb)'::regprocedure);
  if position('return jsonb_set(result' in src)=0 or position('params->''rollover''));' in src)=0 then
    raise exception 'Unexpected simulator definition; affordability decoration not applied';
  end if;
  src := replace(src,'return jsonb_set(result','result := jsonb_set(result');
  src := replace(src,'params->''rollover''));',E'params->''rollover''));\n  return public._debt_scenario_context(params,result);');
  execute src;
end;
$$;
