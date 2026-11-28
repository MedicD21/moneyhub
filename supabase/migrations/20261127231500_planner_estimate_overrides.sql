-- Planner: a pay_date_overrides row can now be flagged as a forecast ESTIMATE.
--
-- Problem: the Planner ignored overtime hours on any paycheck that has a pay_date_overrides amount,
-- on the theory that a real net already includes the overtime. But Claude also uses an override to put
-- KNOWN overtime into the real forecast before the check lands (an estimate), which locked that
-- paycheck in the Planner and stopped Dustin from running scenarios on it.
--
-- Fix: add pay_date_overrides.is_estimate (default false). An override with is_estimate = true is a
-- forecast estimate: the planner treats the paycheck as open and adds planned OT on top of the estimate
-- (the baseline forecast already contains the estimate, so known OT is counted once and scenario OT
-- is extra). An override with is_estimate = false is a real deposit amount and still replaces planned OT.
-- Existing rows default to false, so nothing changes until a row is flagged.
--
-- Only shortfall_plan_forecast changes (has_actual ignores estimates). No other function or view reads
-- the flag, so pay_period_forecast, paycheck_plan, the Dashboard and the real forecast are untouched.
-- The function is patched in place (as 20261127220000 did) and raises before changing anything if the
-- replacement point is not found. One transaction via apply_migration.
do $mig$
declare
  v_def text := pg_get_functiondef('public.shortfall_plan_forecast(jsonb)'::regprocedure);
  v_new text;
begin
  v_new := replace(v_def,
    'and ov.actual_net is not null)), false) as has_actual',
    'and ov.actual_net is not null
                   and not ov.is_estimate)), false) as has_actual');
  if v_new = v_def then raise exception 'planner estimate overrides: has_actual check not found'; end if;

  alter table public.pay_date_overrides
    add column is_estimate boolean not null default false;
  comment on column public.pay_date_overrides.is_estimate is
    'true = actual_net is a forecast estimate (e.g. known overtime added before the check lands). The Planner still lets planned OT be added on top. Replace with the real net and set false when the deposit lands.';

  execute v_new;
end
$mig$;
