-- The starting-cash anchor (seq 1) seeds the running balance but is not itself a future low point:
-- a balance already under the floor before a same-day deposit must not make the period negative.
do $mig$
declare
  v_def text := pg_get_functiondef('public.pay_period_forecast(integer,integer)'::regprocedure);
  v_old1 text := '(select min(b.balance) from bal b where b.ev_date >= greatest(pr.pay_date, cfg.today))';
  v_new1 text := '(select min(b.balance) from bal b where b.seq > 1 and b.ev_date >= greatest(pr.pay_date, cfg.today))';
  v_old2 text := '(select b.ev_date from bal b where b.ev_date >= greatest(pr.pay_date, cfg.today)';
  v_new2 text := '(select b.ev_date from bal b where b.seq > 1 and b.ev_date >= greatest(pr.pay_date, cfg.today)';
begin
  if position(v_old1 in v_def) = 0 or position(v_old2 in v_def) = 0 then
    raise exception 'pay_period_forecast low-point clauses not found; edit manually';
  end if;
  execute replace(replace(v_def, v_old1, v_new1), v_old2, v_new2);
end $mig$;
