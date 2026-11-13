-- Read-only simulation. The private engine is also used for the historical golden
-- regression; its legacy switch is deliberately NOT part of the public RPC.
create or replace function public._simulate_debt_schedule(
  p_debts jsonb, p_params jsonb, p_cashflows jsonb, p_legacy boolean default false
) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  balances jsonb := '{}'; starts jsonb; payments jsonb; interests jsonb; fees jsonb;
  minimums jsonb; removed jsonb; paid jsonb := '{}'; schedule jsonb := '[]';
  principals jsonb := '[]'; payoff_order jsonb := '[]';
  d jsonb; e jsonb; id text; month date; first_month date := (p_params->>'start_month')::date;
  strategy text := p_params->>'strategy'; rollover boolean := (p_params->>'rollover')::boolean;
  balance numeric; principal numeric; rate numeric; n integer; last_payment numeric;
  amount numeric; fee numeric; interest numeric; minimum numeric; pool numeric;
  lump_pool numeric; extra numeric := (p_params->>'extra_monthly')::numeric;
  total_interest numeric := 0; total_fees numeric := 0; total_removed numeric := 0;
  total_payments numeric := 0; unused_cash numeric := 0; month_index integer;
  completed boolean := false; payoff_month text; months integer;
begin
  for d in select value from jsonb_array_elements(p_debts) loop
    id := d->>'id'; balance := (d->>'balance')::numeric; principal := balance;
    if d->>'name' ilike 'Affirm%' and not p_legacy and balance > 0 then
      rate := (d->>'stored_apr')::numeric / 1200;
      n := ceil(balance / (d->>'min_payment')::numeric);
      -- Discount the actual remaining cashflows, including a smaller final
      -- installment. Using n full minimums would invent additional debt.
      last_payment := balance - (n-1) * (d->>'min_payment')::numeric;
      if rate > 0 then
        principal := round((d->>'min_payment')::numeric *
          (1-power(1+rate, -(n-1))) / rate + last_payment / power(1+rate,n), 2);
      end if;
      principals := principals || jsonb_build_array(jsonb_build_object(
        'debt_id',id,'name',d->>'name','stored_balance',balance,
        'derived_principal',principal,'payments_remaining',n,'final_payment',last_payment,
        'frequency',d->>'frequency','valuation_apr',(d->>'stored_apr')::numeric));
    end if;
    balances := jsonb_set(balances,array[id],to_jsonb(principal));
  end loop;
  for month_index in 0..1199 loop
    month := (first_month + make_interval(months => month_index))::date;
    starts := balances; payments := '{}'; interests := '{}'; fees := '{}';
    minimums := '{}'; removed := '{}'; pool := extra; lump_pool := 0;
    -- Only previously retired minimums are eligible for this month's rollover.
    if rollover then
      for d in select value from jsonb_array_elements(p_debts) loop
        if paid ? (d->>'id') then pool := pool + (d->>'min_payment')::numeric; end if;
      end loop;
    end if;
    for e in select value from jsonb_array_elements(p_cashflows) loop
      if e->>'month' = to_char(month,'YYYY-MM') then pool := pool+(e->>'amount')::numeric; end if;
    end loop;
    -- A stopped standalone bill releases its monthly amount. A stopped debt
    -- payment releases its minimum but leaves the obligation outstanding.
    for e in select value from jsonb_array_elements(coalesce(p_params->'drop_payment','[]')) loop
      if month >= ((e->>'from_month')||'-01')::date and e->>'kind' = 'bill' then
        pool := pool + (e->>'amount')::numeric;
      end if;
    end loop;
    -- Lump sums are cash, never implicitly duplicated by payoff_now.
    for e in select value from jsonb_array_elements(coalesce(p_params->'lump_sums','[]')) loop
      if date_trunc('month',(e->>'date')::date)::date = month then
        if e->>'target_debt_id' is null then
          lump_pool := lump_pool + (e->>'amount')::numeric;
        else
          id := e->>'target_debt_id'; amount := least((balances->>id)::numeric,(e->>'amount')::numeric);
          balances := jsonb_set(balances,array[id],to_jsonb((balances->>id)::numeric-amount));
          payments := jsonb_set(payments,array[id],to_jsonb(coalesce((payments->>id)::numeric,0)+amount));
          lump_pool := lump_pool + (e->>'amount')::numeric-amount;
        end if;
      end if;
    end loop;
    if month_index = 0 then
      for id in select value from jsonb_array_elements_text(coalesce(p_params->'payoff_now','[]')) loop
        balance := (balances->>id)::numeric; amount := least(balance,lump_pool);
        lump_pool := lump_pool-amount;
        payments := jsonb_set(payments,array[id],to_jsonb(coalesce((payments->>id)::numeric,0)+amount));
        removed := jsonb_set(removed,array[id],to_jsonb(balance-amount));
        total_removed := total_removed+balance-amount;
        balances := jsonb_set(balances,array[id],'0');
      end loop;
    end if;
    pool := pool+lump_pool;
    -- All scheduled minimums come before any strategy allocation.
    for d in select value from jsonb_array_elements(p_debts) loop
      id := d->>'id'; balance := (balances->>id)::numeric;
      minimum := (d->>'min_payment')::numeric;
      if month = date '2026-11-01' then minimum := (d->>'nov_minimum')::numeric; end if;
      if month = date '2026-12-01' then minimum := (d->>'dec_minimum')::numeric; end if;
      fee := case when balance > 0 and month >= date '2026-12-01' then (d->>'fee')::numeric else 0 end;
      for e in select value from jsonb_array_elements(coalesce(p_params->'drop_payment','[]')) loop
        if month >= ((e->>'from_month')||'-01')::date and e->>'debt_id' = id then
          if e->>'kind' = 'fee' then fee := 0;
          elsif e->>'kind' = 'debt' and balance > 0 then
            pool := pool+minimum; minimum := 0;
          end if;
        end if;
      end loop;
      rate := (d->>'apr')::numeric/1200;
      if p_legacy and d->>'name' ilike 'Affirm%' then rate := 0; end if;
      interest := case when month >= date '2026-12-01' then round(balance*rate,2) else 0 end;
      total_interest := total_interest+interest; total_fees := total_fees+fee;
      interests := jsonb_set(interests,array[id],to_jsonb(interest));
      fees := jsonb_set(fees,array[id],to_jsonb(fee));
      balance := balance+interest+fee; amount := least(balance,minimum);
      minimums := jsonb_set(minimums,array[id],to_jsonb(amount));
      payments := jsonb_set(payments,array[id],to_jsonb(coalesce((payments->>id)::numeric,0)+amount));
      balances := jsonb_set(balances,array[id],to_jsonb(balance-amount));
    end loop;
    for d in
      select value from jsonb_array_elements(p_debts)
      where (value->>'apr')::numeric > 0
        and not (p_legacy and value->>'name' ilike 'Affirm%')
      order by
        case when strategy='custom' then coalesce((select ord from
          jsonb_array_elements_text(coalesce(p_params->'custom','[]')) with ordinality a(val,ord)
          where val=value->>'id'),2147483647) end,
        case when strategy='snowball' then (balances->>(value->>'id'))::numeric end,
        (value->>'apr')::numeric desc, value->>'id'
    loop
      id := d->>'id'; amount := least(pool,(balances->>id)::numeric);
      balances := jsonb_set(balances,array[id],to_jsonb((balances->>id)::numeric-amount));
      payments := jsonb_set(payments,array[id],to_jsonb((payments->>id)::numeric+amount));
      pool := pool-amount;
    end loop;
    unused_cash := unused_cash+pool;
    for d in select value from jsonb_array_elements(p_debts) order by value->>'id' loop
      id := d->>'id'; balance := (balances->>id)::numeric;
      if (starts->>id)::numeric <= 0 then continue; end if;
      total_payments := total_payments+(payments->>id)::numeric;
      schedule := schedule || jsonb_build_array(jsonb_build_object(
        'month',to_char(month,'YYYY-MM'),'debt_id',id,'start',(starts->>id)::numeric,
        'interest',(interests->>id)::numeric,'fee',(fees->>id)::numeric,
        'minimum',(minimums->>id)::numeric,'payment',(payments->>id)::numeric,
        'what_if_removed',coalesce((removed->>id)::numeric,0),'end',balance));
      if balance = 0 and not paid ? id then
        paid := jsonb_set(paid,array[id],to_jsonb(to_char(month,'YYYY-MM')));
        payoff_order := payoff_order || jsonb_build_array(jsonb_build_object(
          'debt_id',id,'name',d->>'name','month',to_char(month,'YYYY-MM')));
      end if;
    end loop;
    if not exists (select 1 from jsonb_each_text(balances) where value::numeric>0) then
      completed := true; payoff_month := to_char(month,'YYYY-MM'); months := month_index+1; exit;
    end if;
  end loop;
  return jsonb_build_object('schedule',schedule,'summary',jsonb_build_object(
    'total_interest',total_interest,'total_fees',total_fees,
    'total_interest_and_fees',total_interest+total_fees,
    'total_payments',total_payments,'what_if_removed',total_removed,'unused_cash',unused_cash,
    'debt_free_month',payoff_month,'months',months,'completed',completed,
    'payoff_order',payoff_order,'per_debt_payoff_month',
      (select coalesce(jsonb_object_agg(key,paid->key),'{}') from jsonb_each(balances)),
    'remaining_balances',balances,'affirm_principals',principals));
end;
$$;
revoke all on function public._simulate_debt_schedule(jsonb,jsonb,jsonb,boolean) from public, anon, authenticated, service_role;

create or replace function public.simulate_debt_plan(p_params jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  owner uuid := public.assert_app_owner(); plan public.debt_plans%rowtype;
  params jsonb; debts jsonb := '[]'; cashflows jsonb := '[]'; drops jsonb := '[]';
  d record; e jsonb; key text; val jsonb; target uuid; label text; kind text;
  start_month date; end_month date; first_min numeric; dec_min numeric; apr numeric;
  extra numeric; amount numeric; hour_net numeric; strategy text; custom jsonb;
  result jsonb; baseline jsonb; legacy jsonb; raise_date date;
begin
  if p_params is null or jsonb_typeof(p_params) <> 'object' then raise exception 'Parameters must be an object'; end if;
  for key in select jsonb_object_keys(p_params) loop
    if key <> all(array['strategy','custom','extra_monthly','lump_sums','payoff_now','drop_payment','raise','overtime','apr_overrides']) then
      raise exception 'Unknown parameter: %',key;
    end if;
    if p_params->key = 'null'::jsonb then raise exception 'Parameter % cannot be null',key; end if;
  end loop;
  select * into plan from public.debt_plans where owner_id=owner and is_active;
  if not found then raise exception 'An active debt plan is required'; end if;
  start_month := date_trunc('month',plan.balances_as_of)::date;
  end_month := (start_month+interval '100 years')::date;
  -- Structured scenario defaults can be saved in assumptions; prose is never executed.
  params := '{}'::jsonb;
  for key in select unnest(array['strategy','custom','extra_monthly','lump_sums','payoff_now','drop_payment','raise','overtime','apr_overrides']) loop
    if plan.assumptions ? key then params := params || jsonb_build_object(key,plan.assumptions->key); end if;
  end loop;
  params := params || p_params;
  strategy := coalesce(params->>'strategy',plan.strategy);
  if strategy not in ('avalanche','snowball','custom','minimums_only') then raise exception 'Unknown strategy'; end if;
  extra := coalesce((params->>'extra_monthly')::numeric,plan.extra_monthly);
  if extra < 0 or extra > 100000000 or extra::text in ('NaN','Infinity','-Infinity') then raise exception 'Invalid extra_monthly'; end if;
  foreach key in array array['lump_sums','payoff_now','drop_payment','overtime','custom'] loop
    if params ? key and jsonb_typeof(params->key) <> 'array' then raise exception '% must be an array',key; end if;
  end loop;
  if params ? 'apr_overrides' and jsonb_typeof(params->'apr_overrides') <> 'object' then raise exception 'apr_overrides must be an object'; end if;
  if exists(select 1 from jsonb_each(coalesce(params->'apr_overrides','{}')) where jsonb_typeof(value)<>'number') then
    raise exception 'APR overrides must be numbers';
  end if;
  if params ? 'raise' and jsonb_typeof(params->'raise') <> 'object' then raise exception 'raise must be an object'; end if;
  custom := coalesce(params->'custom',plan.assumptions->'custom_order','[]');
  if strategy='custom' and jsonb_array_length(custom)=0 then raise exception 'Custom strategy requires custom debt IDs'; end if;
  -- Validate every debt reference, including keys in the override map.
  for key in
    select value from jsonb_array_elements_text(coalesce(params->'payoff_now','[]'))
    union all select value from jsonb_array_elements_text(custom)
    union all select jsonb_object_keys(coalesce(params->'apr_overrides','{}'))
    union all select value->>'target_debt_id' from jsonb_array_elements(coalesce(params->'lump_sums','[]')) where value->>'target_debt_id' is not null
    union all select value->>'debt_id' from jsonb_array_elements(coalesce(params->'drop_payment','[]')) where value->>'debt_id' is not null
  loop
    if key is null or not exists(select 1 from public.debts where id=key::uuid and owner_id=owner and is_active) then
      raise exception 'Unknown active debt: %',key;
    end if;
  end loop;
  -- JSON object lookup is case-sensitive; PostgreSQL UUID equality is not.
  select coalesce(jsonb_agg(to_jsonb(value::uuid)),'[]') into custom from jsonb_array_elements_text(custom);
  if params ? 'payoff_now' then
    select coalesce(jsonb_agg(to_jsonb(value::uuid)),'[]') into val from jsonb_array_elements_text(params->'payoff_now');
    params := jsonb_set(params,'{payoff_now}',val);
  end if;
  foreach key in array array['lump_sums','drop_payment'] loop
    if params ? key then
      label := case when key='lump_sums' then 'target_debt_id' else 'debt_id' end;
      select coalesce(jsonb_agg(case when value->>label is null then value
        else jsonb_set(value,array[label],to_jsonb((value->>label)::uuid)) end),'[]') into val
        from jsonb_array_elements(params->key);
      params := jsonb_set(params,array[key],val);
    end if;
  end loop;
  if params ? 'apr_overrides' then
    select coalesce(jsonb_object_agg(k::uuid,v),'{}') into val from jsonb_each(params->'apr_overrides') a(k,v);
    params := jsonb_set(params,'{apr_overrides}',val);
  end if;
  if (select count(*) <> count(distinct value) from jsonb_array_elements_text(custom)) or
     (select count(*) <> count(distinct value) from jsonb_array_elements_text(coalesce(params->'payoff_now','[]'))) then
    raise exception 'Duplicate debt IDs';
  end if;
  for d in
    select dt.*, db.balance, b.frequency, coalesce(b.due_day,dt.due_day,extract(day from b.anchor_date)::int) payment_day
    from public.debts dt
    left join lateral (select x.balance from public.debt_balances x where x.debt_id=dt.id and x.owner_id=owner
      order by x.as_of_date desc,x.created_at desc,x.id desc limit 1) db on true
    left join public.bills b on b.debt_id=dt.id and b.owner_id=owner and b.is_active
    where dt.owner_id=owner and dt.is_active order by dt.id
  loop
    if d.balance is null then raise exception 'Missing balance for %',d.name; end if;
    if d.balance < 0 then raise exception 'Negative balance for %',d.name; end if;
    if d.balance > 0 and d.min_payment <= 0 then raise exception 'Missing minimum for %',d.name; end if;
    if d.name ilike 'Affirm%' and d.frequency is distinct from 'monthly' then
      raise exception 'Affirm payment frequency must be confirmed monthly: %',d.name;
    end if;
    if d.frequency is not null and d.frequency <> 'monthly' then raise exception 'Unsupported debt frequency: %',d.name; end if;
    apr := coalesce((params->'apr_overrides'->>d.id::text)::numeric,
      case when d.name ilike 'SoFi%' then 22.74 when d.name ilike 'GoodLeap%' then 11.49 else d.apr end);
    if apr < 0 or apr > 1000 or apr::text in ('NaN','Infinity','-Infinity') then raise exception 'Invalid APR'; end if;
    -- The saved November schedule records remaining/retried payments (LoveSac),
    -- which cannot be inferred solely from due_day. December records Ally's extension.
    select (value->>'minimum')::numeric into first_min from jsonb_array_elements(plan.schedule)
      where value->>'debt_id'=d.id::text and value->>'month'='2026-11' limit 1;
    first_min := coalesce(first_min,case when d.payment_day >= extract(day from plan.balances_as_of) then d.min_payment else 0 end);
    dec_min := d.min_payment;
    if d.name ilike 'Ally%' then
      select coalesce((value->>'minimum')::numeric,d.min_payment) into dec_min from jsonb_array_elements(plan.schedule)
        where value->>'debt_id'=d.id::text and value->>'month'='2026-12' limit 1;
      dec_min := coalesce(dec_min,d.min_payment);
    end if;
    debts := debts || jsonb_build_array(jsonb_build_object('id',d.id,'name',d.name,'balance',d.balance,
      'apr',apr,'stored_apr',d.apr,'min_payment',d.min_payment,'nov_minimum',first_min,
      'dec_minimum',dec_min,'fee',case when d.name ilike 'SoFi%' then 10 else 0 end,'frequency',d.frequency));
  end loop;
  for e in select value from jsonb_array_elements(coalesce(params->'lump_sums','[]')) loop
    amount := (e->>'amount')::numeric;
    if jsonb_typeof(e)<>'object' or amount is null or amount < 0 or amount > 100000000 or
       (e->>'date') is null or (e->>'date')::date < start_month or (e->>'date')::date >= end_month then
      raise exception 'Invalid lump sum';
    end if;
  end loop;
  for e in select value from jsonb_array_elements(coalesce(params->'drop_payment','[]')) loop
    if jsonb_typeof(e)<>'object' or coalesce(e->>'from_month','') !~ '^\d{4}-(0[1-9]|1[0-2])$' or
      ((e->>'from_month')||'-01')::date < start_month or
      ((e->>'from_month')||'-01')::date >= end_month or
      ((e->>'debt_id') is null) = ((e->>'label') is null) then raise exception 'Invalid drop_payment'; end if;
    target := null; amount := 0; label := e->>'label';
    if e->>'debt_id' is not null then target := (e->>'debt_id')::uuid; kind := 'debt';
    elsif lower(label) in ('sofi fee','sofi $10 fee','sofi monthly fee') then
      select id into target from public.debts where owner_id=owner and is_active and name ilike 'SoFi%';
      if target is null then raise exception 'Unknown SoFi fee'; end if;
      kind := 'fee';
    else
      if (select count(*) from public.bills where owner_id=owner and is_active and lower(name)=lower(label) and debt_id is null and frequency='monthly') <> 1 then
        raise exception 'Label must identify one active monthly standalone bill';
      end if;
      select b.amount into amount from public.bills b where owner_id=owner and is_active and lower(name)=lower(label) and debt_id is null and frequency='monthly';
      kind := 'bill';
    end if;
    if exists(select 1 from jsonb_array_elements(drops) x where
      (x->>'kind'=kind and (x->>'debt_id'=target::text or x->>'label'=label))) then raise exception 'Duplicate dropped payment'; end if;
    drops := drops || jsonb_build_array(e || jsonb_build_object('kind',kind,'debt_id',target,'amount',amount));
  end loop;
  select extra_hour_net into hour_net from public.app_settings where id and owner_id=owner;
  for e in select value from jsonb_array_elements(coalesce(params->'overtime','[]')) loop
    amount := (e->>'hours')::numeric;
    if jsonb_typeof(e)<>'object' or amount is null or amount < 0 or amount > 744 or
       e->>'pay_date' is null or (e->>'pay_date')::date < start_month or (e->>'pay_date')::date >= end_month then
      raise exception 'Invalid overtime';
    end if;
    cashflows := cashflows || jsonb_build_array(jsonb_build_object('month',to_char((e->>'pay_date')::date,'YYYY-MM'),'amount',round(amount*hour_net,2)));
  end loop;
  if params ? 'raise' then
    raise_date := (params->'raise'->>'effective_date')::date;
    amount := (params->'raise'->>'extra_net_per_paycheck')::numeric;
    if raise_date is null or raise_date >= end_month or amount is null or amount < 0 or amount > 100000000 then raise exception 'Invalid raise'; end if;
    if not exists(select 1 from public.income_sources where owner_id=owner and is_active) then raise exception 'Raise requires an active income source'; end if;
    select cashflows || coalesce(jsonb_agg(jsonb_build_object('month',m,'amount',round(n*amount,2))),'[]') into cashflows
    from (select to_char(p.pay_date,'YYYY-MM') m,count(*) n from public.pay_dates(greatest(start_month,raise_date),end_month-1) p
      join public.income_sources s on s.id=p.income_source_id and s.owner_id=owner group by 1) q;
  end if;
  params := params || jsonb_build_object('start_month',start_month,'strategy',strategy,'custom',custom,
    'extra_monthly',case when strategy='minimums_only' then 0 else extra end,'drop_payment',drops,
    'rollover',strategy<>'minimums_only' and not (p_params ? 'extra_monthly' and extra=0));
  result := public._simulate_debt_schedule(debts,params,cashflows);
  -- Counterfactual baseline uses ORIGINAL APRs and no scenario interventions.
  select coalesce(jsonb_agg(value || jsonb_build_object('apr',case
      when value->>'name' ilike 'SoFi%' then 22.74 when value->>'name' ilike 'GoodLeap%' then 11.49
      else (value->>'stored_apr')::numeric end)),'[]') into val from jsonb_array_elements(debts);
  baseline := public._simulate_debt_schedule(val,jsonb_build_object('start_month',start_month,
    'strategy','minimums_only','extra_monthly',0,'rollover',false),'[]');
  legacy := public._simulate_debt_schedule(val,jsonb_build_object('start_month',start_month,
    'strategy',plan.strategy,'extra_monthly',plan.extra_monthly,'rollover',plan.strategy<>'minimums_only'),'[]',true);
  return jsonb_set(result,'{summary}',result->'summary' || jsonb_build_object(
    'interest_saved_vs_minimums',case when (baseline#>>'{summary,completed}')::boolean and (result#>>'{summary,completed}')::boolean
      then (baseline->'summary'->>'total_interest')::numeric-(result->'summary'->>'total_interest')::numeric end,
    'months_earlier_than_minimums',(baseline->'summary'->>'months')::integer-(result->'summary'->>'months')::integer,
    'minimums_only',baseline->'summary','legacy_comparison',jsonb_build_object(
      'stored_total_interest',plan.summary->'total_interest','stored_debt_free_month',plan.summary->'debt_free_month',
      'recomputed_interest_and_fees',legacy->'summary'->'total_interest_and_fees',
      'recomputed_debt_free_month',legacy->'summary'->'debt_free_month',
      'reason','Legacy includes SoFi fees in interest and treats Affirm balances as fixed payments. New model discounts Affirm cashflows, charges interest, and allows early payoff; fees are reported separately.'),
    'start_month',to_char(start_month,'YYYY-MM'),'rollover',params->'rollover'));
end;
$$;
revoke all on function public.simulate_debt_plan(jsonb) from public, anon;
grant execute on function public.simulate_debt_plan(jsonb) to authenticated;
comment on function public.simulate_debt_plan(jsonb) is
  'Owner-only, read-only debt simulation. Omitted extra inherits active rollover; explicit extra_monthly=0 disables rollover. See docs/debt-simulation.md.';
