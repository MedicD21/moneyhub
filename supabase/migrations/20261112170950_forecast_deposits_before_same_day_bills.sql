-- Same-day order in pay_period_forecast: deposits post before that day's bills (direct deposit
-- lands early morning / days early). Outflow-first made every payday dip below the floor before
-- its own paycheck and pinned the binding low point to period starts.
do $mig$
declare
  v_def text := pg_get_functiondef('public.pay_period_forecast(integer,integer)'::regprocedure);
  v_old text := 'case when e.kind = ''start'' then -1 when e.amount < 0 then 0 else 1 end';
  v_new text := 'case when e.kind = ''start'' then -1 when e.amount >= 0 then 0 else 1 end';
begin
  if position(v_old in v_def) = 0 then
    raise exception 'pay_period_forecast ordering clause not found; edit manually';
  end if;
  execute replace(v_def, v_old, v_new);
end $mig$;
