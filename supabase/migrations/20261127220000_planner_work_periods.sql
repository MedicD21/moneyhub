-- Planner: show the work period each paycheck pays for.
--
-- Dustin's example: the Dec 9 paycheck pays for Nov 21 - Dec 4. The work period is 14 days and ends 5 days
-- before the SCHEDULED payday (the pay_date_overrides scheduled_date when the payday was moved, so a holiday
-- week that pays early or late still maps to the same work period). Checked against his Nov 25 check
-- (paid Nov 24): work period Nov 7 - Nov 20, which holds Veterans Day, as its note says.
-- This adds work_start and work_end to every row of shortfall_plan_forecast().plan_periods. Display only:
-- no balance, suggestion or other number changes. Patches the applied function in place (as
-- 20261127200000_extra_debt_targets did for paycheck_plan) and raises before changing anything if a
-- replacement point is not found. One transaction via apply_migration.
do $mig$
declare
  v_def text := pg_get_functiondef('public.shortfall_plan_forecast(jsonb)'::regprocedure);
  v_new text;
begin
  v_new := replace(v_def,
    'inc.deposit_date, inc.income_amount, inc.received, inc.has_actual',
    'inc.deposit_date, inc.income_amount, inc.received, inc.has_actual, inc.sched_date');
  if v_new = v_def then raise exception 'planner work periods: select list not found'; end if;
  v_def := v_new;

  v_new := replace(v_def,
    'coalesce(sum((it->>''amount'')::numeric), 0) as income_amount,',
    'coalesce(sum((it->>''amount'')::numeric), 0) as income_amount,
               coalesce(min(coalesce((select ov.scheduled_date from public.pay_date_overrides ov
                                       where ov.income_source_id = (it->>''id'')::uuid
                                         and ov.actual_date = (it->>''date'')::date limit 1),
                                     (it->>''date'')::date)), s.pay_date) as sched_date,');
  if v_new = v_def then raise exception 'planner work periods: income lateral not found'; end if;
  v_def := v_new;

  v_new := replace(v_def,
    '  r            record;',
    '  v_lag        constant integer := 5;   -- work period ends this many days before the scheduled payday
  v_len        constant integer := 14;  -- work period length in days
  r            record;');
  if v_new = v_def then raise exception 'planner work periods: declare block not found'; end if;
  v_def := v_new;

  v_new := replace(v_def,
    '''is_current'', r.is_current,',
    '''is_current'', r.is_current,
      ''work_start'', r.sched_date - (v_lag + v_len - 1),
      ''work_end'', r.sched_date - v_lag,');
  if v_new = v_def then raise exception 'planner work periods: row object not found'; end if;

  execute v_new;
end;
$mig$;
