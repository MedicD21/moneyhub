-- =============================================================================
-- Money Hub — date / schedule functions
--   adjust_business_day, recurring_dates, pay_dates, bill_due_dates,
--   ensure_bill_occurrences
-- =============================================================================

-- Move a Saturday/Sunday date to Friday (previous) or Monday (next).
create or replace function public.adjust_business_day(p_date date, p_mode text)
returns date
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when p_mode = 'previous_business_day' and extract(isodow from p_date) = 6 then p_date - 1
    when p_mode = 'previous_business_day' and extract(isodow from p_date) = 7 then p_date - 2
    when p_mode = 'next_business_day'     and extract(isodow from p_date) = 6 then p_date + 2
    when p_mode = 'next_business_day'     and extract(isodow from p_date) = 7 then p_date + 1
    else p_date
  end;
$$;

-- Clamp a day-of-month to the last day of the given month.
create or replace function public.clamp_day(p_year int, p_month int, p_day int)
returns date
language sql
immutable
parallel safe
set search_path = ''
as $$
  select make_date(p_year, p_month,
    least(p_day, extract(day from (make_date(p_year, p_month, 1) + interval '1 month - 1 day'))::int));
$$;

-- Every date of a recurring schedule that falls in [p_from, p_through].
--   weekly / biweekly : step 7 / 14 days from p_anchor (anchor may be past or future)
--   monthly           : p_days[1] (or anchor's day) every month, clamped to month end
--   semimonthly       : each of p_days every month, clamped (and de-duplicated)
--   quarterly         : day every 3 months, phase from the anchor's month
--   annual            : day in the anchor's month every year
create or replace function public.recurring_dates(
  p_frequency text, p_anchor date, p_days int[], p_from date, p_through date)
returns setof date
language sql
immutable
rows 30
set search_path = ''
as $$
  with params as (
    select
      case p_frequency when 'weekly' then 7 when 'biweekly' then 14 end as step,
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
$$;

-- Paydays in [p_start, p_end] (inclusive) for every active income source.
create or replace function public.pay_dates(p_start date, p_end date)
returns table (income_source_id uuid, pay_date date, expected_net numeric)
language sql
stable
rows 30
security invoker
set search_path = ''
as $$
  select s.id, adj.pay_date, s.expected_net
  from public.income_sources s
  cross join lateral (
    -- widen by 3 days so a weekend shift can move a date into/out of range
    select public.adjust_business_day(r, s.weekend_adjust) as pay_date
    from public.recurring_dates(
           s.frequency, s.anchor_date,
           case when s.frequency = 'semimonthly' then s.semimonthly_days end,
           p_start - 3, p_end + 3) r
  ) adj
  where s.is_active
    and adj.pay_date between p_start and p_end
  order by adj.pay_date, s.name;
$$;
comment on function public.pay_dates(date, date) is
  'Paydays in [p_start, p_end] for active income sources (weekend-adjusted per source).';

-- Due dates of one bill in [p_from, p_through].
create or replace function public.bill_due_dates(
  p_frequency text, p_due_day int, p_anchor date, p_from date, p_through date)
returns setof date
language sql
immutable
rows 12
set search_path = ''
as $$
  select public.recurring_dates(
    p_frequency,
    -- monthly bills may be defined by due_day alone; give them a nominal anchor
    coalesce(p_anchor, make_date(2000, 1, coalesce(p_due_day, 1))),
    case when p_due_day is not null and p_frequency in ('monthly','quarterly','annual')
         then array[p_due_day] end,
    p_from, p_through);
$$;

-- Create any missing bill_occurrences from the start of the current month
-- through p_through (default: today + 60 days). Idempotent.
create or replace function public.ensure_bill_occurrences(p_through date default null)
returns int
language plpgsql
security invoker
set search_path = ''
as $$
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
  on conflict (bill_id, due_date) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
comment on function public.ensure_bill_occurrences(date) is
  'Creates missing bill_occurrences from the 1st of this month through p_through (default today+60). Returns rows created.';
