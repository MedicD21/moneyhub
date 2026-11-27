-- Name the debt(s) that each paycheck's "Extra debt payment (active plan)" goes to.
--
-- paycheck_plan() already adds one extra_debt item per paycheck (the plan's payments above minimums for the month,
-- spread over the paychecks in a year). This adds a 'targets' array to that item: [{debt_id, name, amount}], taken
-- from the active plan's schedule rows for that month where payment > minimum (rollover plus any extra). Each
-- target's share is its part of the month's extra, rounded to cents; the last target takes the rounding remainder
-- so the targets always add up exactly to the item's amount. No amount, total or forecast number changes.
--
-- 1. debt_plan_extra_split(month, amount, extra_month): the split (internal helper; stable, no table writes).
-- 2. paycheck_plan(): the extra_debt item gains 'targets' (patched in place; raises if the clause is not found).

create or replace function public.debt_plan_extra_split(p_date date, p_amount numeric, p_extra_month numeric)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with rows as (
    select e->>'debt_id' as debt_id,
           round(sum((e->>'payment')::numeric - (e->>'minimum')::numeric), 2) as extra
    from public.debt_plans p
    cross join lateral jsonb_array_elements(p.schedule) e
    where p.is_active
      and e ? 'minimum'
      and left(e->>'month', 7) = to_char(p_date, 'YYYY-MM')
    group by e->>'debt_id'
    having sum((e->>'payment')::numeric - (e->>'minimum')::numeric) > 0.004
  ),
  named as (
    select r.debt_id, coalesce(d.name, 'Unknown debt') as name, r.extra,
           row_number() over (order by r.extra desc, coalesce(d.name, ''), r.debt_id) as rn,
           count(*) over () as n
    from rows r
    left join public.debts d on d.id::text = r.debt_id
  ),
  shares as (
    select n.*, round(p_amount * n.extra / nullif(p_extra_month, 0), 2) as share
    from named n
  ),
  fin as (
    select s.debt_id, s.name, s.rn,
           case when s.rn = s.n
                then round(p_amount - coalesce(sum(s.share) over (order by s.rn rows between unbounded preceding and 1 preceding), 0), 2)
                else s.share
           end as amount
    from shares s
  )
  select coalesce(jsonb_agg(jsonb_build_object('debt_id', f.debt_id, 'name', f.name, 'amount', f.amount) order by f.rn), '[]'::jsonb)
  from fin f;
$function$;
comment on function public.debt_plan_extra_split(date, numeric, numeric) is
  'Splits a paycheck''s extra debt payment across the debts the active plan pays above minimum in that month: [{debt_id, name, amount}], adding up exactly to p_amount.';
revoke execute on function public.debt_plan_extra_split(date, numeric, numeric) from public, anon;
grant execute on function public.debt_plan_extra_split(date, numeric, numeric) to authenticated;

do $mig$
declare
  v_def text := pg_get_functiondef('public.paycheck_plan(date)'::regprocedure);
  v_old text := E'        ''extra_monthly'', v_extra_month, ''paydays_per_year'', v_paydays_year));';
  v_new text := E'        ''extra_monthly'', v_extra_month, ''paydays_per_year'', v_paydays_year,\n        ''targets'', public.debt_plan_extra_split(v_start, v_extra, v_extra_month)));';
begin
  if position(v_old in v_def) = 0 then
    raise exception 'paycheck_plan extra-debt item not found; edit manually';
  end if;
  execute replace(v_def, v_old, v_new);
end $mig$;
