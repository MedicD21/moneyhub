-- Applied to the remote project on 2026-11-12 via the Supabase connector; committed here so the
-- repo matches supabase_migrations.schema_migrations (version 20261112163926).

-- 1) Support a 42-day income cadence (used to model a long/long/short biweekly rotation as three staggered sources)
alter table public.income_sources drop constraint income_sources_frequency_check;
alter table public.income_sources add constraint income_sources_frequency_check
  check (frequency = any (array['weekly','biweekly','every_6_weeks','semimonthly','monthly']));

create or replace function public.recurring_dates(p_frequency text, p_anchor date, p_days integer[], p_from date, p_through date)
 returns setof date
 language sql
 immutable rows 30
 set search_path to ''
as $function$
  with params as (
    select
      case p_frequency when 'weekly' then 7 when 'biweekly' then 14 when 'every_6_weeks' then 42 end as step,
      coalesce(p_days, array[extract(day from p_anchor)::int]) as days
  ),
  stepped as (
    select g::date as d
    from params p,
         generate_series(
           (p_anchor + (ceil((p_from - p_anchor)::numeric / p.step) * p.step)::int)::timestamp,
           p_through::timestamp,
           make_interval(days => p.step)) g
    where p.step is not null and p_anchor is not null
  ),
  months as (
    select m::date as m
    from generate_series(date_trunc('month', p_from::timestamp), date_trunc('month', p_through::timestamp), interval '1 month') m
    where p_frequency in ('monthly','semimonthly','quarterly','annual')
  ),
  monthly as (
    select distinct public.clamp_day(extract(year from mo.m)::int, extract(month from mo.m)::int, dd) as d
    from months mo, params p, unnest(p.days) dd
    where case p_frequency
            when 'monthly'     then true
            when 'semimonthly' then true
            when 'quarterly'   then mod(((extract(year from mo.m) * 12 + extract(month from mo.m))
                                         - (extract(year from p_anchor) * 12 + extract(month from p_anchor)))::int
                                        + 1200, 3) = 0
            when 'annual'      then extract(month from mo.m) = extract(month from p_anchor)
          end
  )
  select d from stepped
  union
  select d from monthly where d between p_from and p_through
  order by 1;
$function$;

-- 2) Bills can end (installment plans)
alter table public.bills add column end_date date;
comment on column public.bills.end_date is 'Last due date (inclusive). No occurrences are generated or projected after it. NULL = open-ended.';
alter table public.bills add constraint bills_end_after_anchor check (end_date is null or anchor_date is null or end_date >= anchor_date);

create or replace function public.ensure_bill_occurrences(p_through date default null::date)
 returns integer
 language plpgsql
 set search_path to ''
as $function$
declare
  v_from    date := date_trunc('month', public.app_today()::timestamp)::date;
  v_through date := coalesce(p_through, public.app_today() + 60);
  v_count   int;
begin
  insert into public.bill_occurrences (owner_id, bill_id, due_date, expected_amount)
  select b.owner_id, b.id, d, b.amount
  from public.bills b
  cross join lateral public.bill_due_dates(b.frequency, b.due_day, b.anchor_date, v_from, v_through) d
  where b.is_active
    and (b.end_date is null or d <= b.end_date)
  on conflict (bill_id, due_date) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

create or replace function public.sync_bill_occurrences_on_bill_change()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if new.amount is distinct from old.amount then
    update public.bill_occurrences o
       set expected_amount = new.amount
     where o.bill_id = new.id and o.status = 'due' and o.paid_amount is null
       and o.due_date >= public.app_today();
  end if;

  if (old.is_active and not new.is_active)
     or new.frequency   is distinct from old.frequency
     or new.due_day     is distinct from old.due_day
     or new.anchor_date is distinct from old.anchor_date then
    delete from public.bill_occurrences o
     where o.bill_id = new.id and o.status = 'due' and o.paid_amount is null
       and o.due_date >= public.app_today()
       and not exists (select 1 from public.transactions t where t.bill_occurrence_id = o.id);
  end if;

  -- end date moved earlier / set: drop unpaid occurrences past it
  if new.end_date is not null and new.end_date is distinct from old.end_date then
    delete from public.bill_occurrences o
     where o.bill_id = new.id and o.status = 'due' and o.paid_amount is null
       and o.due_date > new.end_date
       and not exists (select 1 from public.transactions t where t.bill_occurrence_id = o.id);
  end if;

  if new.is_active and (not old.is_active
                        or new.frequency   is distinct from old.frequency
                        or new.due_day     is distinct from old.due_day
                        or new.anchor_date is distinct from old.anchor_date
                        or new.end_date    is distinct from old.end_date) then
    perform public.ensure_bill_occurrences();
  end if;
  return new;
end;
$function$;

drop trigger sync_bill_occurrences on public.bills;
create trigger sync_bill_occurrences
  after update of amount, is_active, frequency, due_day, anchor_date, end_date on public.bills
  for each row execute function public.sync_bill_occurrences_on_bill_change();

-- paycheck_plan: stop projecting bills past end_date (targeted edit; fails loudly if the source changed)
do $mig$
declare
  v_def text := pg_get_functiondef('public.paycheck_plan(date)'::regprocedure);
  v_old text := E'    where b.is_active\n      and not exists (select 1 from public.bill_occurrences o where o.bill_id = b.id and o.due_date = d)';
  v_new text := E'    where b.is_active\n      and (b.end_date is null or d <= b.end_date)\n      and not exists (select 1 from public.bill_occurrences o where o.bill_id = b.id and o.due_date = d)';
begin
  if position(v_old in v_def) = 0 then
    raise exception 'paycheck_plan projection clause not found; edit manually';
  end if;
  execute replace(v_def, v_old, v_new);
end
$mig$;

create or replace view public.v_monthly_bills_total as
 select coalesce(round(sum(monthly), 2), 0::numeric) as monthly_total,
    coalesce(round(sum(monthly) filter (where autopay), 2), 0::numeric) as autopay_monthly_total,
    coalesce(round(sum(monthly) filter (where is_variable), 2), 0::numeric) as variable_monthly_total,
    count(*) as active_bill_count
   from ( select b.autopay,
            b.is_variable,
                case b.frequency
                    when 'weekly' then b.amount * 52 / 12
                    when 'biweekly' then b.amount * 26 / 12
                    when 'monthly' then b.amount
                    when 'quarterly' then b.amount / 3
                    when 'annual' then b.amount / 12
                    else null::numeric
                end as monthly
           from public.bills b
          where b.is_active
            and (b.end_date is null or b.end_date >= public.app_today())) m;
